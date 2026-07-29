require "rails_helper"

RSpec.describe Claims::PersonalInformation::NormalizeClassifierResult do
  let!(:type) do
    Claims::PersonalInformationType.find_or_create_by!(
      type_key: "government_identifier"
    ) do |row|
      row.display_name = "Government identifier"
      row.description = "Government identifiers not needed for review."
      row.enabled = true
      row.sort_order = 20
    end
  end

  it "accepts and resolves a valid high-risk result" do
    reason = "A possible government identifier appears on page 2."
    result =
      described_class.call(
        classifier_payload: {
          "personal_information_review_status" => "high_risk",
          "personal_information_type_key" => type.type_key,
          "personal_information_review_reason" => reason
        }
      )

    expect(result).to eq(
      personal_information_review_status: "high_risk",
      personal_information_type_id: type.id,
      personal_information_review_reason: reason
    )
  end

  it "accepts not-flagged, unable-to-assess, and legacy payload shapes" do
    expect(
      described_class.call(
        classifier_payload: {
          personal_information_review_status: "not_flagged",
          personal_information_type_key: nil,
          personal_information_review_reason: nil
        }
      )
    ).to eq(
      personal_information_review_status: "not_flagged",
      personal_information_type_id: nil,
      personal_information_review_reason: nil
    )

    expect(
      described_class.call(
        classifier_payload: {
          "personal_information_review_status" => "unable_to_assess",
          "personal_information_type_key" => nil,
          "personal_information_review_reason" =>
            "The file is unreadable and could not be assessed."
        }
      )
    ).to include(
      personal_information_review_status: "unable_to_assess",
      personal_information_type_id: nil
    )

    expect(
      described_class.call(classifier_payload: { "document_kind" => "invoice" })
    ).to eq({})
  end

  it "rejects incomplete and invalid status combinations" do
    expect do
      described_class.call(
        classifier_payload: {
          "personal_information_review_status" => "high_risk"
        }
      )
    end.to raise_error(ArgumentError, /incomplete/)

    expect do
      described_class.call(
        classifier_payload: {
          "personal_information_review_status" => "not_flagged",
          "personal_information_type_key" => type.type_key,
          "personal_information_review_reason" => nil
        }
      )
    end.to raise_error(ArgumentError, /not_flagged/)

    expect do
      described_class.call(
        classifier_payload: {
          "personal_information_review_status" => "high_risk",
          "personal_information_type_key" => type.type_key,
          "personal_information_review_reason" => " "
        }
      )
    end.to raise_error(ArgumentError, /nonblank reason/)
  end

  it "rejects an unknown or disabled configured type" do
    disabled =
      Claims::PersonalInformationType.create!(
        type_key: "disabled_#{SecureRandom.hex(4)}",
        display_name: "Disabled",
        description: "Not available to the classifier.",
        enabled: false,
        sort_order: 900
      )

    [disabled.type_key, "not_configured"].each do |type_key|
      expect do
        described_class.call(
          classifier_payload: {
            "personal_information_review_status" => "review_recommended",
            "personal_information_type_key" => type_key,
            "personal_information_review_reason" =>
              "Unexpected personal information is visible."
          }
        )
      end.to raise_error(ArgumentError, /Unknown or disabled/)
    end
  end
end
