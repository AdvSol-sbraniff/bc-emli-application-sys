require "json"

PROGRAM_SLUG = "energy-savings-program".freeze
SUBMISSION_TYPE_NAME = "Invoice".freeze
EXPORT_GLOB =
  Rails
    .root
    .join(
      "claims_ai_service_ddl",
      "reference_data",
      "silver_templates",
      "silver_template_*.json"
    )
    .freeze

def parse_bundle(path)
  raw = File.read(path)
  JSON.parse(raw)
rescue JSON::ParserError
  JSON.parse(raw.split("|", 2).last)
end

def find_local_template!(bundle)
  variant_name = bundle.dig("requirement_template", "submission_variant_name")
  raise "Missing submission_variant_name in bundle" if variant_name.blank?

  template =
    RequirementTemplate
      .joins(:program)
      .joins(
        "INNER JOIN permit_classifications submission_type_pc ON submission_type_pc.id = requirement_templates.submission_type_id"
      )
      .joins(
        "INNER JOIN permit_classifications submission_variant_pc ON submission_variant_pc.id = requirement_templates.submission_variant_id"
      )
      .where(
        :programs => {
          slug: PROGRAM_SLUG
        },
        "submission_type_pc.name" => SUBMISSION_TYPE_NAME,
        "submission_variant_pc.name" => variant_name
      )
      .where(discarded_at: nil)
      .first

  raise "No local template found for variant #{variant_name}" if template.blank?

  template
end

def ensure_published_version!(template)
  template.published_template_version ||
    template.template_versions.create!(
      version_date: Date.current,
      status: "published",
      form_json: {
      },
      requirement_blocks_json: {
      },
      denormalized_template_json: {
      }
    )
end

files = Dir.glob(EXPORT_GLOB.to_s).sort
raise "No Silver export bundles found under #{EXPORT_GLOB}" if files.empty?

results = []

ActiveRecord::Base.transaction do
  files.each do |path|
    bundle = parse_bundle(path)
    silver_template = bundle.fetch("requirement_template")
    silver_version = bundle.fetch("published_template_version")

    local_template = find_local_template!(bundle)
    published_version = ensure_published_version!(local_template)

    local_template.update!(
      nickname: silver_template["nickname"],
      description: silver_template["description"]
    )

    published_version.update!(
      version_date: Date.parse(silver_version.fetch("version_date")),
      status: "published",
      form_json: silver_version.fetch("form_json"),
      requirement_blocks_json: silver_version.fetch("requirement_blocks_json"),
      denormalized_template_json:
        silver_version.fetch("denormalized_template_json")
    )

    results << {
      file: File.basename(path),
      variant: silver_template["submission_variant_name"],
      local_requirement_template_id: local_template.id,
      local_template_version_id: published_version.id
    }
  end
end

puts JSON.pretty_generate(results)
