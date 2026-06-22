require "rails_helper"

RSpec.describe Claims::RunGenaiJob do
  describe "#product_enrichment_context" do
    it "filters stale eligibility-code lookups out of user record 6 context" do
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
      lookup_result = {
        lookups: {
          eligibility_code: {
            matched: true,
            evidence_kind: "invoice_eligibility_code",
            evidence_value: "ESP1-NatGas9c0f0033"
          }
        }
      }

      context =
        described_class.new.send(
          :product_enrichment_context,
          invoice_version: invoice_version,
          lookup_result: lookup_result
        )

      expect(context).to include(
        record_name: "download_product_enrichment",
        available: false,
        matches: []
      )
      expect(context.fetch(:reason)).to eq(
        "No product lookup was required for the detected upgrade types."
      )
    end
  end
end
