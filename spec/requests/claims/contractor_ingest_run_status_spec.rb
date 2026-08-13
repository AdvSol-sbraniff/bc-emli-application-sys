require "rails_helper"

RSpec.describe "Claims contractor ingest run status", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_contractor
    ).and_return(contractor)
  end

  let(:contractor) do
    Contractor.create!(business_name: "Single Polling Contractor")
  end

  it "returns the resolved invoice and readiness in the run response" do
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck",
        status_updated_at: Time.current
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "single-poll/invoice.pdf",
        original_filename: "Invoice.pdf",
        content_type: "application/pdf"
      )
    ingest_run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_version_id: invoice_version.id,
        status: "succeeded",
        total_files: 1,
        completed_files: 1,
        failed_files: 0,
        completed_at: Time.current
      )
    Claims::IngestStepRun.create!(
      ingest_run_id: ingest_run.id,
      session_id: session.id,
      invoice_version_id: invoice_version.id,
      step_type: "case_facts",
      status: "failed",
      error_text: "Malformed first response",
      failure_category: "technical_failure",
      failure_code: "genai_service_malformed_response",
      retryable: true
    )

    get "/api/claims/contractor/ingest/runs/#{ingest_run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "id" => ingest_run.id,
      "status" => "succeeded",
      "presentation_state" => "ready",
      "upgrade_type_scope_change" => nil,
      "invoice_id" => invoice.id,
      "invoice_status" => "contractor_precheck",
      "invoice_version_id" => invoice_version.id,
      "invoice_versionno" => 1,
      "original_filename" => "Invoice.pdf",
      "can_continue" => true
    )
    expect(json_response.fetch("failure_category")).to be_nil
    expect(json_response.fetch("failure_message")).to be_nil
  end

  it "returns processing invoice context without allowing continuation" do
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
        storage_provider: "azure_blob",
        storage_key: "single-poll/processing.pdf",
        original_filename: "Processing.pdf",
        content_type: "application/pdf"
      )
    ingest_run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        status: "running",
        total_files: 2,
        completed_files: 0,
        failed_files: 0
      )
    Claims::IngestStepRun.create!(
      ingest_run_id: ingest_run.id,
      session_id: session.id,
      invoice_version_id: invoice_version.id,
      step_type: "case_facts",
      status: "failed",
      error_text: "Malformed first response",
      failure_category: "technical_failure",
      failure_code: "genai_service_malformed_response",
      retryable: true
    )

    get "/api/claims/contractor/ingest/runs/#{ingest_run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "status" => "running",
      "presentation_state" => "processing",
      "invoice_id" => invoice.id,
      "invoice_status" => "contractor_precheck",
      "invoice_version_id" => invoice_version.id,
      "can_continue" => false
    )
    expect(json_response.fetch("failure_category")).to be_nil
    expect(json_response.fetch("failure_message")).to be_nil
  end

  it "keeps succeeded run readiness after the invoice advances in business workflow" do
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_revision_inbox"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "completed-run/advanced-invoice.pdf",
        original_filename: "Advanced invoice.pdf",
        content_type: "application/pdf"
      )
    run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_version_id: invoice_version.id,
        status: "succeeded",
        total_files: 1,
        completed_files: 1,
        completed_at: Time.current
      )

    get "/api/claims/contractor/ingest/runs/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "presentation_state" => "ready",
      "invoice_status" => "contractor_revision_inbox",
      "can_continue" => true
    )
  end

  it "returns one contractor-facing failure from the authoritative run response" do
    session = Claims::Session.create!
    ingest_run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        status: "failed",
        total_files: 2,
        completed_files: 0,
        failed_files: 1,
        completed_at: Time.current,
        failure_category: "technical_failure",
        failure_code: "genai_service_error"
      )
    Claims::IngestStepRun.create!(
      ingest_run_id: ingest_run.id,
      session_id: session.id,
      step_type: "classify_document",
      status: "failed",
      error_text: "Private provider failure.",
      failure_category: "technical_failure",
      failure_code: "genai_service_error",
      error_code: "genai_provider_gateway_error",
      error_category: "provider_gateway_error",
      retryable: true,
      diagnostic_id: "private-diagnostic",
      provider_status: 503,
      provider_code: "service_unavailable"
    )

    get "/api/claims/contractor/ingest/runs/#{ingest_run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "status" => "failed",
      "presentation_state" => "failed",
      "failure_category" => "technical_failure",
      "failure_code" => "genai_service_error",
      "can_continue" => false
    )
    expect(json_response.fetch("failure_message")).to be_present
    expect(json_response).not_to have_key("messages")
    expect(json_response.to_json).not_to include("provider_status")
    expect(json_response.to_json).not_to include("private-diagnostic")
    expect(json_response.fetch("invoice_id")).to be_nil
  end

  it "derives changed upgrade types for a rejected fix without stored messages" do
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_revision_inbox"
      )
    source =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "scope/source.pdf",
        original_filename: "Original invoice.pdf",
        content_type: "application/pdf"
      )
    electrical =
      Claims::InvoiceUpgradeType.find_or_create_by!(
        upgrade_type_key: "electrical_service_upgrade"
      ) { |row| row.description = "Electrical service upgrade" }
    heat_pump =
      Claims::InvoiceUpgradeType.find_or_create_by!(
        upgrade_type_key: "air_source_heat_pump_gas_propane"
      ) { |row| row.description = "Air source heat pump" }
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: source.id,
      invoice_upgrade_type_id: electrical.id,
      confidence: 99
    )
    run =
      Claims::IngestRun.create!(
        run_kind: "fix_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        status: "failed",
        total_files: 1,
        completed_files: 0,
        failed_files: 1,
        failure_category: "package_needs_correction",
        failure_code: "package_replacement_upgrade_types_changed",
        pipeline_error_code: "fix_upgrade_types_changed",
        pipeline_error_description:
          "Replacement invoice changed the claimed upgrade types.",
        completed_at: Time.current
      )
    Claims::IngestDocument.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      contractor_id: contractor.id,
      invoice_id: invoice.id,
      resolved_invoice_id: invoice.id,
      storage_provider: "azure_blob",
      storage_key: "scope/replacement.pdf",
      original_filename: "Changed invoice.pdf",
      content_type: "application/pdf",
      classifier_raw_json: {
        "detected_upgrade_types" => [
          { "upgrade_type_key" => electrical.upgrade_type_key },
          { "upgrade_type_key" => heat_pump.upgrade_type_key }
        ]
      },
      document_kind: "invoice",
      document_kind_confidence: 99,
      classification_confidence: 99
    )

    get "/api/claims/contractor/ingest/runs/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("upgrade_type_scope_change")).to include(
      "replacement_filename" => "Changed invoice.pdf",
      "added_upgrade_types" => [
        a_hash_including("upgrade_type_key" => heat_pump.upgrade_type_key)
      ],
      "removed_upgrade_types" => []
    )
    expect(json_response).not_to have_key("messages")
  end
end
