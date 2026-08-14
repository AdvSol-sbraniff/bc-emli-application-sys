require "rails_helper"

RSpec.describe "Claims admin ingest runs", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
  end

  def create_run(contractor:, status: "failed", created_at: Time.current)
    session =
      Claims::Session.create!(created_at: created_at, updated_at: created_at)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id:
          (contractor || Contractor.create!(business_name: "Run Owner")).id,
        status: "contractor_precheck",
        created_at: created_at,
        updated_at: created_at
      )
    invoice_version =
      if status == "succeeded"
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "test",
          storage_key: "admin-runs/#{invoice.id}.pdf",
          original_filename: "Invoice.pdf",
          content_type: "application/pdf",
          created_at: created_at,
          updated_at: created_at
        )
      end

    attributes = {
      run_kind: "initial_upload",
      session_id: session.id,
      invoice_id: invoice.id,
      contractor_id: contractor&.id,
      status: status,
      total_files: 2,
      completed_files: status == "succeeded" ? 2 : 0,
      failed_files: status == "failed" ? 1 : 0,
      failure_category: status == "failed" ? "package_needs_correction" : nil,
      failure_code: status == "failed" ? "package_unreadable_file" : nil,
      resolved_invoice_version_id: invoice_version&.id,
      pipeline_error_code:
        status == "failed" ? "genai_input_image_invalid" : nil,
      pipeline_error_description:
        status == "failed" ? "classify_document failed after 1 attempt." : nil,
      created_at: created_at,
      updated_at: created_at,
      completed_at: created_at
    }
    Claims::IngestRun.create!(attributes)
  end

  context "with claims-admin access" do
    before do
      allow_any_instance_of(Api::Claims::IngestRunsAdminController).to receive(
        :require_claims_admin!
      )
    end

    it "returns view-backed run rows with contractor display fields" do
      contractor =
        Contractor.create!(
          business_name: "Readable Ingest Contractor",
          number: "ING-42"
        )
      run = create_run(contractor: contractor)
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        step_type: "stage_package",
        status: "failed",
        error_text: "Provider rejected an image.",
        failure_category: "package_needs_correction",
        failure_code: "package_unreadable_file",
        error_code: "genai_input_image_invalid",
        error_category: "provider_invalid_image",
        retryable: false,
        diagnostic_id: "diag-admin-grid",
        provider_status: 400,
        provider_code: "invalid_payload",
        created_at: Time.current,
        updated_at: Time.current
      )
      create_run(contractor: nil, status: "succeeded", created_at: 1.minute.ago)

      get "/api/claims/admin/ingest_runs",
          params: {
            q: "Readable Ingest",
            status: "failed",
            sort: "created_at:desc"
          }

      expect(response).to have_http_status(:ok)
      expect(json_response.fetch("rows")).to contain_exactly(
        hash_including(
          "id" => run.id,
          "contractor_id" => contractor.id,
          "contractor_business_name" => "Readable Ingest Contractor",
          "contractor_number" => "ING-42",
          "status" => "failed",
          "duration_seconds" => 0.0,
          "pipeline_error_code" => "genai_input_image_invalid",
          "attempt_summary" =>
            hash_including(
              "failed_attempts" => 1,
              "recovered_attempts" => 0,
              "failed_targets" => 1
            ),
          "terminal_failure" =>
            hash_including(
              "error_code" => "genai_input_image_invalid",
              "diagnostic_id" => "diag-admin-grid",
              "provider_status" => 400,
              "provider_code" => "invalid_payload",
              "retryable" => false
            )
        )
      )
      expect(json_response.fetch("rows").first).not_to have_key("messages")
      expect(json_response.dig("meta", "total")).to eq(1)

      get "/api/claims/admin/ingest_runs/#{run.id}"

      expect(response).to have_http_status(:ok)
      expect(json_response).to include(
        "id" => run.id,
        "contractor_id" => contractor.id,
        "contractor_business_name" => "Readable Ingest Contractor",
        "contractor_number" => "ING-42",
        "status" => "failed",
        "pipeline_error_code" => "genai_input_image_invalid"
      )
      expect(json_response.fetch("terminal_failure")).to include(
        "error_code" => "genai_input_image_invalid",
        "diagnostic_id" => "diag-admin-grid"
      )
    end

    it "returns only step runs belonging to the selected ingest run" do
      contractor = Contractor.create!(business_name: "Step Grid Contractor")
      selected_run = create_run(contractor: contractor)
      other_run = create_run(contractor: contractor, status: "succeeded")
      ingest_document =
        Claims::IngestDocument.create!(
          ingest_run_id: selected_run.id,
          session_id: selected_run.session_id,
          contractor_id: contractor.id,
          storage_provider: "azure_blob",
          storage_key: "failed/source-photo.jpg",
          original_filename: "Original source photo.jpg",
          content_type: "image/jpeg"
        )
      selected_step =
        Claims::IngestStepRun.create!(
          ingest_run_id: selected_run.id,
          session_id: selected_run.session_id,
          ingest_document_id: ingest_document.id,
          step_type: "classify_document",
          status: "failed",
          error_text: "Retained failure: genai_input_image_invalid.",
          failure_category: "package_needs_correction",
          failure_code: "package_unreadable_file",
          error_code: "genai_input_image_invalid",
          retryable: false,
          created_at: Time.current,
          updated_at: Time.current
        )
      Claims::IngestStepRun.create!(
        ingest_run_id: other_run.id,
        session_id: other_run.session_id,
        step_type: "stage_package",
        status: "succeeded",
        created_at: Time.current,
        updated_at: Time.current
      )

      get "/api/claims/admin/ingest_runs/#{selected_run.id}/steps"

      expect(response).to have_http_status(:ok)
      expect(json_response.fetch("rows")).to contain_exactly(
        hash_including(
          "id" => selected_step.id,
          "ingest_run_id" => selected_run.id,
          "ingest_document_id" => ingest_document.id,
          "ingest_document_original_filename" => "Original source photo.jpg",
          "step_type" => "classify_document",
          "status" => "failed",
          "display_status" => "failed",
          "attempt_number" => 1,
          "attempt_count" => 1,
          "effective_attempt" => true,
          "error_code" => "genai_input_image_invalid",
          "retryable" => false,
          "has_di_results_json" => false,
          "has_genai_results_json" => false,
          "has_context_window_json" => false
        )
      )
      expect(json_response.fetch("rows").first).not_to have_key(
        "genai_results_json"
      )
      expect(
        json_response.fetch("rows").first.fetch("completed_at")
      ).to be_present
      expect(
        json_response.fetch("rows").first.fetch("duration_seconds")
      ).to be >= 0
      expect(json_response.dig("meta", "ingest_run_id")).to eq(selected_run.id)

      get "/api/claims/admin/ingest_step_runs/#{selected_step.id}"

      expect(response).to have_http_status(:ok)
      expect(json_response).to include(
        "id" => selected_step.id,
        "ingest_document_original_filename" => "Original source photo.jpg",
        "genai_results_json" => nil,
        "error_code" => "genai_input_image_invalid",
        "display_status" => "failed",
        "attempt_number" => 1,
        "retryable" => false
      )
      expect(json_response.fetch("completed_at")).to be_present
      expect(json_response.fetch("duration_seconds")).to be >= 0
    end

    it "reports recovered attempts without presenting a terminal failure" do
      run = create_run(contractor: nil, status: "succeeded")
      failed_step =
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: run.session_id,
          step_type: "case_facts",
          status: "failed",
          error_text: "Malformed first response.",
          error_code: "genai_model_output_invalid_json",
          retryable: true,
          diagnostic_id: "diag-recovered-attempt",
          created_at: 1.minute.ago,
          updated_at: 1.minute.ago
        )
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        step_type: "case_facts",
        status: "succeeded",
        created_at: Time.current,
        updated_at: Time.current
      )

      get "/api/claims/admin/ingest_runs/#{run.id}"

      expect(response).to have_http_status(:ok)
      expect(json_response.fetch("status")).to eq("succeeded")
      expect(json_response.fetch("terminal_failure")).to be_nil
      expect(json_response.fetch("attempt_summary")).to include(
        "failed_attempts" => 1,
        "recovered_attempts" => 1,
        "retried_targets" => 1,
        "failed_targets" => 0
      )

      get "/api/claims/admin/ingest_runs/#{run.id}/steps"

      recovered =
        json_response
          .fetch("rows")
          .find { |row| row.fetch("id") == failed_step.id }
      expect(recovered).to include(
        "display_status" => "recovered",
        "logical_state" => "succeeded",
        "attempt_number" => 1,
        "attempt_count" => 2,
        "effective_attempt" => false
      )
    end

    it "finds a run by a retained step diagnostic identifier" do
      run = create_run(contractor: nil)
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        step_type: "case_facts",
        status: "failed",
        error_text: "Provider unavailable.",
        error_code: "genai_service_unavailable",
        retryable: false,
        diagnostic_id: "diag-search-exact-value"
      )

      get "/api/claims/admin/ingest_runs",
          params: {
            q: "diag-search-exact-value"
          }

      expect(response).to have_http_status(:ok)
      expect(json_response.fetch("rows").pluck("id")).to eq([run.id])
    end
  end

  it "rejects non-admin users" do
    participant = build(:user, :submitter)
    allow_any_instance_of(Api::Claims::IngestRunsAdminController).to receive(
      :current_user
    ).and_return(participant)

    get "/api/claims/admin/ingest_runs"

    expect(response).to have_http_status(:forbidden)
    expect(json_response).to include(
      "error" => "Claims function access required.",
      "required_function" => "claims.configuration"
    )
  end
end
