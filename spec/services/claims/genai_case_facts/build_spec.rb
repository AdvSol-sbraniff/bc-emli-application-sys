require "rails_helper"

RSpec.describe Claims::GenaiCaseFacts::Build do
  describe ".build_shared_context" do
    it "resolves eligibility and participant identity from the classifier eligibility code" do
      eligibility_code = "ESP1-CASE-#{SecureRandom.hex(4)}"
      participant =
        create(
          :user,
          first_name: "David",
          last_name: "Holmes",
          email: "david.holmes@example.com"
        )
      eligibility =
        Claims::UsersEligibilitycode.create!(
          user: participant,
          eligibility_code: eligibility_code,
          applied_at: Time.zone.parse("2026-06-01"),
          approved_at: Time.zone.parse("2026-06-20"),
          expires_at: Time.zone.parse("2026-06-25")
        )
      contractor =
        Contractor.create!(
          business_name: "Centra Windows Ltd",
          street_address: "4795 102 ave se",
          city: "Calgary",
          postal_code: "T2C 2X7"
        )
      session = Claims::Session.create!
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "contractor_precheck"
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_key: "invoice.pdf"
        )

      shared_context =
        described_class.build_shared_context(
          sess: session,
          invoice: invoice,
          eligibility_code: " #{eligibility_code} "
        )
      described_class.persist_identity_references!(
        invoice_version_id: invoice_version.id,
        identity_references: shared_context.fetch(:identity_references)
      )

      facts = shared_context.fetch(:case_facts).fetch(:esp_database_values)
      expect(facts.dig(:users, :participant_name)).to eq("David Holmes")
      expect(facts.dig(:users_eligibilitycodes, :eligibility_code)).to eq(
        eligibility_code
      )
      expect(shared_context.fetch(:identity_references)).to eq(
        users_eligibilitycode_id: eligibility.id,
        participant_user_id: participant.id
      )
      expect(invoice_version.reload.users_eligibilitycode_id).to eq(
        eligibility.id
      )
      expect(invoice_version.participant_user_id).to eq(participant.id)
    end

    it "clears stale identity UUIDs when the classifier eligibility code does not resolve" do
      eligibility_code = "ESP1-OLD-#{SecureRandom.hex(4)}"
      participant = create(:user)
      eligibility =
        Claims::UsersEligibilitycode.create!(
          user: participant,
          eligibility_code: eligibility_code,
          applied_at: Time.zone.parse("2026-06-01"),
          approved_at: Time.zone.parse("2026-06-02"),
          expires_at: Time.zone.parse("2026-06-30")
        )
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "contractor_precheck"
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_key: "invoice.pdf",
          users_eligibilitycode_id: eligibility.id,
          participant_user_id: participant.id
        )

      shared_context =
        described_class.build_shared_context(
          sess: session,
          invoice: invoice,
          eligibility_code: "NOT-A-REAL-CODE"
        )
      described_class.persist_identity_references!(
        invoice_version_id: invoice_version.id,
        identity_references: shared_context.fetch(:identity_references)
      )

      expect(invoice_version.reload.users_eligibilitycode_id).to be_nil
      expect(invoice_version.participant_user_id).to be_nil
    end
  end

  describe ".supporting_document_context_for_upgrade_type" do
    it "includes complete OCR text for a PI-flagged supporting document" do
      contractor = Contractor.create!(business_name: "Evidence Contractor")
      session = Claims::Session.create!
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "contractor_precheck"
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_key: "invoice.pdf"
        )
      upgrade_type =
        Claims::InvoiceUpgradeType.find_or_create_by!(
          upgrade_type_key: "electrical_service_upgrade"
        ) { |row| row.description = "Electrical service upgrade" }
      document_type =
        Claims::SupportingDocumentType.find_or_create_by!(
          type_key: "other_supporting_document"
        ) do |row|
          row.description = "Other Supporting Document"
          row.enabled = true
        end
      pi_type =
        Claims::PersonalInformationType.find_or_create_by!(
          type_key: "government_identifier"
        ) do |row|
          row.display_name = "Government identifier"
          row.description = "Government identification."
          row.enabled = true
          row.sort_order = 20
        end
      ocr_text = [
        "Electrical upgrade evidence.",
        "A" * 1_600,
        "Heat pump installation completed 2026-03-15 on page two."
      ].join("\n")
      Claims::SupportingDocument.create!(
        invoice_version_id: invoice_version.id,
        supporting_document_type_id: document_type.id,
        storage_key: "flagged-utility-document.pdf",
        personal_information_review_status: "high_risk",
        personal_information_type_id: pi_type.id,
        personal_information_review_reason:
          "A possible government identifier requires admin review.",
        di_read_raw_json: {
          "content" => ocr_text
        }
      )

      context =
        described_class.supporting_document_context_for_upgrade_type(
          invoice_version: invoice_version,
          invoice_upgrade_type: upgrade_type
        )
      expect(context.fetch(:configured_documents)).to be_empty
      document = context.fetch(:other_documents).sole

      expect(document.fetch(:ocr_text)).to eq(ocr_text)
      expect(document.fetch(:ocr_text)).to end_with(
        "Heat pump installation completed 2026-03-15 on page two."
      )
      expect(document).to include(
        personal_information_review_status: "high_risk"
      )
      expect(document).not_to have_key(:ocr_text_excerpt)
    end
  end
end
