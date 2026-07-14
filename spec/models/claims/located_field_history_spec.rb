require "rails_helper"

RSpec.describe "Claims located-field definition history" do
  it "snapshots the previous code-field definition before an update" do
    row =
      Claims::CodeLocatedField.create!(
        code_field_key: "spec.code.#{SecureRandom.hex(4)}",
        contractor_display_name: "Original code label",
        description: "Original description",
        enabled: true
      )

    row.update!(
      contractor_display_name: "Updated code label",
      description: "Updated description"
    )

    history = Claims::CodeLocatedFieldHistory.where(source_id: row.id).sole
    expect(history).to have_attributes(
      contractor_display_name: "Original code label",
      description: "Original description"
    )
  end

  it "snapshots the previous GenAI-field definition before an update" do
    row =
      Claims::GenaiLocatedField.create!(
        genai_field_key: "spec_genai_#{SecureRandom.hex(4)}",
        contractor_display_name: "Original GenAI label",
        prompt_text: "Original prompt",
        enabled: true
      )

    row.update!(
      contractor_display_name: "Updated GenAI label",
      prompt_text: "Updated prompt"
    )

    history = Claims::GenaiLocatedFieldHistory.where(source_id: row.id).sole
    expect(history).to have_attributes(
      contractor_display_name: "Original GenAI label",
      prompt_text: "Original prompt"
    )
  end
end
