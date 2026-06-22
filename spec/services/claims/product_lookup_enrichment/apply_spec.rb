require "rails_helper"

RSpec.describe Claims::ProductLookupEnrichment::Apply do
  describe ".call" do
    it "does not own eligibility or participant UUID enrichment" do
      eligibility_code = "ESP1-PROD-#{SecureRandom.hex(4)}"
      participant = create(:user)
      eligibility =
        Claims::UsersEligibilitycode.create!(
          user: participant,
          eligibility_code: eligibility_code,
          applied_at: Time.zone.parse("2026-06-01"),
          approved_at: Time.zone.parse("2026-06-20"),
          expires_at: Time.zone.parse("2026-06-25")
        )
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_in_progress"
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_key: "invoice.pdf"
        )
      common_upgrade_type =
        Claims::InvoiceUpgradeType.find_or_create_by!(
          upgrade_type_key: "common"
        )
      Claims::InvoiceVersionLocatedField.create!(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: common_upgrade_type.id,
        source_engine: "classifier",
        field_key: "classifier.eligibility_code",
        value_type: "text",
        value_text: eligibility.eligibility_code,
        confidence: 100
      )

      result =
        described_class.call(
          invoice_version_id: invoice_version.id,
          invoice_upgrade_types: []
        )

      expect(result).to include(ok: true, skipped: true)
      expect(result.fetch(:lookups)).to eq({})
      expect(result.fetch(:updated_columns)).to eq([])
      expect(invoice_version.reload.users_eligibilitycode_id).to be_nil
      expect(invoice_version.participant_user_id).to be_nil
    end
  end
end
