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
    Claims::IngestRun.create!(
      session_id: session.id,
      contractor_id: contractor&.id,
      status: status,
      total_files: 2,
      completed_files: status == "succeeded" ? 2 : 0,
      failed_files: status == "failed" ? 1 : 0,
      pipeline_error_code:
        status == "failed" ? "genai_input_image_invalid" : nil,
      pipeline_error_description:
        status == "failed" ? "classifier_files failed after 1 attempt." : nil,
      created_at: created_at,
      updated_at: created_at,
      completed_at: created_at
    )
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
        step_type: "upload_package_stage",
        status: "failed",
        error_text: "Provider rejected an image.",
        failure_status: "package_needs_correction",
        failure_status_subtype: "package_unreadable_file",
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
          "primary_failure" =>
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
      expect(json_response.fetch("primary_failure")).to include(
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
          step_type: "classifier_files",
          status: "failed",
          error_text: "Retained failure: genai_input_image_invalid.",
          failure_status: "package_needs_correction",
          failure_status_subtype: "package_unreadable_file",
          error_code: "genai_input_image_invalid",
          retryable: false,
          created_at: Time.current,
          updated_at: Time.current
        )
      Claims::IngestStepRun.create!(
        ingest_run_id: other_run.id,
        session_id: other_run.session_id,
        step_type: "upload_package_stage",
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
          "step_type" => "classifier_files",
          "status" => "failed",
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
        "retryable" => false
      )
      expect(json_response.fetch("completed_at")).to be_present
      expect(json_response.fetch("duration_seconds")).to be >= 0
    end
  end

  it "rejects non-admin users" do
    participant = build(:user, :submitter)
    allow_any_instance_of(Api::Claims::IngestRunsAdminController).to receive(
      :current_user
    ).and_return(participant)

    get "/api/claims/admin/ingest_runs"

    expect(response).to have_http_status(:forbidden)
    expect(json_response.fetch("error")).to eq("Claims admin access required.")
  end
end
