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
          status: "genai_in_progress"
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
          status: "genai_in_progress"
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
end
