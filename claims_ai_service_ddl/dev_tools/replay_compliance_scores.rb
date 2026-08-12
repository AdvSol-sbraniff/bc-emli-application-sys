# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

iterations = Integer(ENV.fetch("ITERATIONS", "10"))
raise ArgumentError, "ITERATIONS must be positive" unless iterations.positive?

invoice_version =
  if ENV["INVOICE_VERSION_ID"].present?
    Claims::InvoiceVersion.find(ENV.fetch("INVOICE_VERSION_ID"))
  else
    Claims::InvoiceVersion.order(updated_at: :desc, id: :desc).first!
  end
invoice = invoice_version.invoice
ingest_run =
  if ENV["INGEST_RUN_ID"].present?
    Claims::IngestRun.find(ENV.fetch("INGEST_RUN_ID"))
  else
    Claims::IngestRun
      .where(resolved_invoice_version_id: invoice_version.id)
      .order(updated_at: :desc, id: :desc)
      .first!
  end

job = Claims::RunGenaiJob.new
classifier_payload =
  job.send(:classifier_payload_from_evidence, invoice_version: invoice_version)
case_facts = job.send(:case_facts_from_step!, invoice_version.id, ingest_run.id)
upgrade_types =
  [job.send(:upgrade_type_by_key!, "common")] +
    job.send(:detected_upgrade_types, classifier_payload)

contexts =
  upgrade_types.to_h do |upgrade_type|
    compiled = job.send(:compiled_user_record1_for_upgrade_type!, upgrade_type)
    context =
      job.send(
        :build_contextwindowjson,
        compiled_user_record1: compiled,
        case_facts: case_facts,
        invoice_version_id: invoice_version.id,
        invoice: invoice,
        upgrade_type: upgrade_type,
        classifier_payload: classifier_payload,
        di_raw_json: invoice_version.di_raw_json
      )
    serialized = JSON.generate(context)
    [
      upgrade_type.upgrade_type_key,
      {
        upgrade_type: upgrade_type,
        context: context,
        context_sha256: Digest::SHA256.hexdigest(serialized),
        context_bytes: serialized.bytesize
      }
    ]
  end

results = []
mutex = Mutex.new
started_at = Time.current

iterations.times do |iteration_index|
  threads =
    contexts.map do |upgrade_type_key, entry|
      Thread.new do
        call_started_at = Time.current
        record = {
          iteration: iteration_index + 1,
          upgrade_type_key: upgrade_type_key,
          context_sha256: entry.fetch(:context_sha256),
          started_at: call_started_at.iso8601(6)
        }

        begin
          payload =
            Claims::Genai::NodeClient.call(
              contextwindowjson: entry.fetch(:context),
              diagnostic_context: {
                step_type: "compliance_score_replay",
                ingest_run_id: ingest_run.id,
                invoice_version_id: invoice_version.id,
                invoice_upgrade_type_id: entry.fetch(:upgrade_type).id,
                replay_iteration: iteration_index + 1
              }
            )
          record[:payload] = payload
          record[:ok] = true
        rescue StandardError => e
          record[:ok] = false
          record[:error_class] = e.class.name
          record[:error] = e.message
        ensure
          record[:elapsed_seconds] = (Time.current - call_started_at).round(3)
          mutex.synchronize do
            results << record
            if record[:ok]
              compact_rules =
                Array(record.dig(:payload, "rulechecks")).map do |rule|
                  "#{rule["rule_key"]}=#{rule["rule_result"]}:#{rule["compliance_score"]}"
                end
              puts(
                "iteration=#{record[:iteration]} " \
                  "ruleset=#{upgrade_type_key} " \
                  "elapsed=#{record[:elapsed_seconds]}s " \
                  "#{compact_rules.join(" | ")}"
              )
            else
              warn(
                "iteration=#{record[:iteration]} " \
                  "ruleset=#{upgrade_type_key} ERROR " \
                  "#{record[:error_class]}: #{record[:error]}"
              )
            end
          end
        end
      end
    end
  threads.each(&:join)
end

expected_result_for_score =
  lambda do |score|
    case score
    when 0..24
      "fail"
    when 25..49
      "warn"
    when 50..74
      "info"
    when 75..100
      "pass"
    end
  end

rule_observations = Hash.new { |hash, key| hash[key] = [] }
contract_errors = []
results
  .select { |record| record[:ok] }
  .each do |record|
    rules = Array(record.dig(:payload, "rulechecks"))
    rules.each do |rule|
      score = Integer(rule["compliance_score"], exception: false)
      result = rule["rule_result"].to_s
      key = "#{record[:upgrade_type_key]}.#{rule["rule_key"]}"
      observation = {
        iteration: record[:iteration],
        result: result,
        compliance_score: score
      }
      rule_observations[key] << observation

      expected_result = expected_result_for_score.call(score) if score
      if score.nil? || expected_result != result
        contract_errors << observation.merge(
          rule: key,
          expected_result: expected_result
        )
      end
    end
  end

boundaries = [25, 50, 75].freeze
rule_summary =
  rule_observations.sort.to_h do |key, observations|
    scores = observations.filter_map { |row| row[:compliance_score] }
    results_seen = observations.map { |row| row[:result] }
    nearest_boundary_distances =
      scores.map do |score|
        boundaries.map { |boundary| (score - boundary).abs }.min
      end
    [
      key,
      {
        calls: observations.length,
        result_counts: results_seen.tally,
        flipped: results_seen.uniq.length > 1,
        scores: scores,
        score_min: scores.min,
        score_max: scores.max,
        score_spread: scores.empty? ? nil : scores.max - scores.min,
        minimum_boundary_distance: nearest_boundary_distances.min,
        mean_boundary_distance:
          if nearest_boundary_distances.empty?
            nil
          else
            (
              nearest_boundary_distances.sum.fdiv(
                nearest_boundary_distances.length
              )
            ).round(2)
          end
      }
    ]
  end

output = {
  generated_at: Time.current.iso8601(6),
  elapsed_seconds: (Time.current - started_at).round(3),
  iterations: iterations,
  invoice_id: invoice.id,
  invoice_version_id: invoice_version.id,
  ingest_run_id: ingest_run.id,
  original_filename: invoice_version.original_filename,
  contexts:
    contexts.transform_values do |entry|
      {
        sha256: entry.fetch(:context_sha256),
        bytes: entry.fetch(:context_bytes)
      }
    end,
  call_count: results.length,
  successful_call_count: results.count { |record| record[:ok] },
  failed_call_count: results.count { |record| !record[:ok] },
  contract_errors: contract_errors,
  rule_summary: rule_summary,
  raw_results:
    results.sort_by { |record| [record[:iteration], record[:upgrade_type_key]] }
}

output_path =
  ENV["OUTPUT_PATH"].presence ||
    Rails
      .root
      .join(
        ".codex_tmp",
        "compliance-score-replay-#{Time.current.strftime("%Y%m%d-%H%M%S")}.json"
      )
      .to_s
FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(output))

puts "OUTPUT_PATH=#{output_path}"
puts "CALLS=#{output[:successful_call_count]}/#{output[:call_count]}"
puts "CONTRACT_ERRORS=#{contract_errors.length}"
rule_summary.each do |key, summary|
  puts(
    "SUMMARY #{key} results=#{summary[:result_counts]} " \
      "scores=#{summary[:scores].join(",")} " \
      "spread=#{summary[:score_spread]} " \
      "min_boundary_distance=#{summary[:minimum_boundary_distance]}"
  )
end
