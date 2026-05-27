require "json"

PROGRAM_SLUG = "energy-savings-program".freeze
SUBMISSION_TYPE_NAME = "Invoice".freeze

def patch_form_components!(node)
  patched = 0

  case node
  when Array
    node.each { |child| patched += patch_form_components!(child) }
  when Hash
    if node["type"] == "simplefile"
      node["validate"] ||= {}
      if node["validate"]["required"] != false
        node["validate"]["required"] = false
        patched += 1
      end
    end

    node.each_value { |child| patched += patch_form_components!(child) }
  end

  patched
end

def patch_requirement_blocks!(blocks_json)
  patched = 0
  return patched unless blocks_json.is_a?(Hash)

  blocks_json.each_value do |block|
    next unless block.is_a?(Hash)

    patched += patch_form_components!(block["form_json"])

    Array(block["requirements"]).each do |requirement|
      next unless requirement.is_a?(Hash)

      is_file_requirement =
        requirement["input_type"] == "file" ||
          requirement.dig("form_json", "type") == "simplefile"

      next unless is_file_requirement

      if requirement["required"] != false
        requirement["required"] = false
        patched += 1
      end

      requirement["form_json"] ||= {}
      requirement["form_json"]["validate"] ||= {}
      if requirement["form_json"]["validate"]["required"] != false
        requirement["form_json"]["validate"]["required"] = false
        patched += 1
      end
    end
  end

  patched
end

def invoice_templates
  RequirementTemplate
    .joins(:program)
    .joins(
      "INNER JOIN permit_classifications submission_type_pc ON submission_type_pc.id = requirement_templates.submission_type_id"
    )
    .where(
      :programs => {
        slug: PROGRAM_SLUG
      },
      "submission_type_pc.name" => SUBMISSION_TYPE_NAME,
      :discarded_at => nil
    )
    .includes(:submission_variant, :published_template_version)
    .order(:created_at)
end

results = []

ActiveRecord::Base.transaction do
  invoice_templates.each do |template|
    version = template.published_template_version
    next unless version

    form_json = JSON.parse(JSON.generate(version.form_json || {}))
    requirement_blocks_json =
      JSON.parse(JSON.generate(version.requirement_blocks_json || {}))
    denormalized_template_json =
      JSON.parse(JSON.generate(version.denormalized_template_json || {}))

    patched_count = 0
    patched_count += patch_form_components!(form_json)
    patched_count += patch_requirement_blocks!(requirement_blocks_json)
    patched_count += patch_requirement_blocks!(denormalized_template_json)
    patched_count += patch_form_components!(denormalized_template_json)

    version.update!(
      form_json: form_json,
      requirement_blocks_json: requirement_blocks_json,
      denormalized_template_json: denormalized_template_json
    )

    results << {
      variant: template.submission_variant&.name,
      template_version_id: version.id,
      patched_count: patched_count
    }
  end
end

puts JSON.pretty_generate(results)
