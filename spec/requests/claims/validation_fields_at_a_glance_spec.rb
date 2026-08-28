require "rails_helper"

RSpec.describe "Claims GenAI fields at a glance data", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(
      Api::Claims::ValidationRulesAdminController
    ).to receive(:require_claims_admin!)
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
  end

  it "returns one field with every mapped upgrade type and prompt position" do
    suffix = SecureRandom.hex(5)
    upgrade_types =
      3.times.map do |index|
        Claims::InvoiceUpgradeType.create!(
          upgrade_type_key: "field_glance_hp_#{index}_#{suffix}",
          description: "Field glance heat pump #{index}"
        )
      end
    field =
      Claims::GenaiLocatedField.create!(
        genai_field_key: "field_glance_ahri_#{suffix}",
        contractor_display_name: "AHRI reference",
        prompt_text: "Locate the visible AHRI reference.",
        enabled: true
      )

    upgrade_types.each_with_index do |upgrade_type, index|
      Claims::GenaiLocatedFieldUpgradeType.create!(
        genai_located_field: field,
        invoice_upgrade_type: upgrade_type,
        field_number: index + 4
      )
    end

    get(
      "/api/claims/admin/validation_rules",
      params: {
        record_type: "genai_located_field",
        q: field.genai_field_key
      }
    )

    expect(response).to have_http_status(:ok)
    matching_rows =
      JSON
        .parse(response.body)
        .fetch("rows")
        .select { |row| row.fetch("id") == field.id }
    expect(matching_rows.length).to eq(1)

    row = matching_rows.first
    expect(row.fetch("record_type")).to eq("genai_located_field")
    expect(row.fetch("upgrade_types").pluck("id")).to match_array(
      upgrade_types.map(&:id)
    )
    expect(
      row
        .fetch("mappings")
        .to_h do |mapping|
          [
            mapping.fetch("invoice_upgrade_type_id"),
            mapping.fetch("field_number")
          ]
        end
    ).to eq(
      upgrade_types.each_with_index.to_h do |upgrade_type, index|
        [upgrade_type.id, index + 4]
      end
    )
  end
end
