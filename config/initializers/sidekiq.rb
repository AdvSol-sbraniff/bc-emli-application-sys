require "sidekiq-cron"
require "sidekiq-unique-jobs"

# Shared configuration for all environments
SHARED_QUEUES = %w[
  claims_ocr
  claims_genai
  virus_scan
  file_processing
  webhooks
  websocket
  model_callbacks
  default
].freeze
AWS_CREDENTIAL_CRON_NAMES = %w[
  aws_credential_refresh
  aws_credential_health_check
].freeze

def sidekiq_queues_from_env
  raw = ENV["SIDEKIQ_QUEUES"].to_s
  queues = raw.split(",").map(&:strip).reject(&:empty?)
  queues.empty? ? SHARED_QUEUES : queues
end

def configure_sidekiq_client(config, redis_cfg = nil)
  config.redis = redis_cfg if redis_cfg

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end
end

def configure_sidekiq_server(config, redis_cfg = nil, concurrency = nil)
  config.redis = redis_cfg if redis_cfg
  config.queues = sidekiq_queues_from_env
  config.concurrency = concurrency || 10 # Default to 10 workers for better throughput

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  config.server_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Server
  end

  SidekiqUniqueJobs::Server.configure(config)
end

def aws_credential_cron_enabled?
  !(
    Rails.env.test? || ENV["IS_DOCKER_BUILD"].present? ||
      ENV["BCGOV_OBJECT_STORAGE_ACCESS_KEY_ID"].blank?
  )
end

def load_sidekiq_cron_schedule(schedule_file)
  return unless File.exist?(schedule_file)

  schedule = YAML.load_file(schedule_file)
  unless aws_credential_cron_enabled?
    AWS_CREDENTIAL_CRON_NAMES.each do |name|
      Sidekiq::Cron::Job.find(name)&.destroy
      schedule.delete(name)
    end
  end
  Sidekiq::Cron::Job.load_from_hash(schedule)
end

# Environment-specific configuration
if Rails.env.production? && ENV["IS_DOCKER_BUILD"].blank? # skip this during precompilation in the docker build stage
  redis_cfg = {
    name: ENV["REDIS_SENTINEL_MASTER_SET_NAME"],
    driver: :ruby,
    sentinels:
      Resolv
        .getaddresses(ENV["REDIS_SENTINEL_HEADLESS"])
        .map do |address|
          { host: address, port: (ENV["REDIS_SENTINEL_PORT"]&.to_i || 26_379) }
        end,
    db: (ENV["SIDEKIQ_REDIS_DB"] || 0).to_i,
    role: :master
  }

  Sidekiq.configure_server do |config|
    configure_sidekiq_server(config, redis_cfg, ENV["SIDEKIQ_CONCURRENCY"].to_i)
  end

  Sidekiq.configure_client do |config|
    configure_sidekiq_client(config, redis_cfg)
  end

  # Load cron schedule in production only
  schedule_file = "config/sidekiq_cron_schedule.yml"
  load_sidekiq_cron_schedule(schedule_file)
elsif Rails.env.development?
  # Development configuration uses default Redis connection
  dev_concurrency = ENV["SIDEKIQ_CONCURRENCY"].to_i
  dev_concurrency = nil if dev_concurrency <= 0

  Sidekiq.configure_server do |config|
    configure_sidekiq_server(config, nil, dev_concurrency)
  end

  Sidekiq.configure_client { |config| configure_sidekiq_client(config) }

  # Load cron schedule in development for testing
  schedule_file = "config/sidekiq_cron_schedule.yml"
  load_sidekiq_cron_schedule(schedule_file)
end
