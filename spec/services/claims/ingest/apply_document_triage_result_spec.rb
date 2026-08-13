require "rails_helper"

RSpec.describe Claims::Ingest::ApplyDocumentTriageResult do
  describe ".call" do
    it "routes clearly supporting evidence with no recognized specific type to the catchall" do
      contractor = Contractor.create!(business_name: "Catchall Contractor")
      session = Claims::Session.create!
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "contractor_precheck"
        )
      run =
        Claims::IngestRun.create!(
          run_kind: "initial_upload",
          session_id: session.id,
          contractor_id: contractor.id,
          status: "running",
          total_files: 1
        )
      document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          storage_key: "support/unusual-completion-record.pdf",
          original_filename: "Unusual completion record.pdf",
          content_type: "application/pdf",
          di_read_raw_json: {
            "content" => "Heat pump installation completed March 15, 2026."
          }
        )
      catchall =
        Claims::SupportingDocumentType.find_or_create_by!(
          type_key: "other_supporting_document"
        ) do |row|
          row.description = "Other Supporting Document"
          row.enabled = true
        end
      catchall.update!(enabled: true)

      result =
        described_class.call(
          ingest_document_id: document.id,
          triage_payload: {
            "document_kind" => "supporting_document",
            "document_kind_confidence" => 94,
            "document_kind_reason" =>
              "This is supplementary completion evidence, not the primary invoice.",
            "supporting_document_type_key" => "unrecognized_completion_record",
            "supporting_document_type_confidence" => 88,
            "supporting_document_type_reason" =>
              "The completion record does not match a more specific type.",
            "supporting_document_routing_quality" => "usable",
            "supporting_document_routing_quality_reason" =>
              "The completion date and work description are readable.",
            "personal_information_review_status" => "not_flagged",
            "personal_information_type_key" => nil,
            "personal_information_review_reason" => nil
          }
        )

      expect(result).to include(
        ok: true,
        document_kind: "supporting_document",
        supporting_document_type_key: "other_supporting_document",
        supporting_document_routing_quality: "usable"
      )
      expect(document.reload).to have_attributes(
        document_kind: "supporting_document",
        supporting_document_type_id: catchall.id
      )
    end
  end
end
