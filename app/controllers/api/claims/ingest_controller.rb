# app/controllers/api/claims/ingest_controller.rb

# ============================================================
# SECTION 00 — FILE OVERVIEW
# PURPOSE: Claims ingest endpoints (POC)
# NOTES:
# - Currently exposes only: POST upload (multipart pdfs[])
# - Returns structured "run report" JSON for React admin screen
# - Logs via Rails.logger (docker compose logs -f app)
# ============================================================

# ============================================================
# SECTION 01 — CONTROLLER: Api::Claims::IngestController
# ============================================================


module Api
  module Claims
    class IngestController < Api::ApplicationController
      # POC: don’t require login + don’t require policy checks

      # ============================================================
      # SECTION 01.01 — AUTH / POLICY BYPASSES (POC ONLY)
      # PURPOSE: Allow testing without login/policy/CSRF friction.
      # ============================================================


skip_before_action :authenticate_user!, only: %i[upload runs_index steps_index steps_by_session_index run_ocr]
skip_before_action :require_confirmation, only: %i[upload runs_index steps_index steps_by_session_index run_ocr]
skip_after_action  :verify_authorized,   only: %i[upload runs_index steps_index steps_by_session_index run_ocr]
skip_forgery_protection only: %i[upload runs_index steps_index steps_by_session_index run_ocr]



# ============================================================
# SECTION 01.50 — ACTION: runs_index
# ROUTE: GET /api/claims/ingest/runs
# PURPOSE:
# - Returns recent claims.ingest_runs rows for the Run Tracker grid
# - Optional filter: ?session_id=<uuid>
# - Optional limit:  ?limit=25 (max 100)
# ============================================================

def runs_index
  session_id = params[:session_id].to_s.strip
  session_id = nil if session_id.empty?

  limit = params[:limit].to_i
  limit = 25 if limit <= 0
  limit = 100 if limit > 100

  scope = ::Claims::IngestRun.order(created_at: :desc)
  scope = scope.where(session_id: session_id) if session_id

  rows = scope.limit(limit).map do |r|
    {
      id: r.id,
      session_id: r.session_id,
      status: r.status,
      total_files: r.total_files,
      completed_files: r.completed_files,
      failed_files: r.failed_files,
      created_at: r.created_at,
      updated_at: r.updated_at,
      completed_at: r.completed_at
    }
  end

  render json: { runs: rows }, status: :ok

rescue => e
  Rails.logger.error("[claims][ingest][runs_index] ERROR: #{e.class}: #{e.message}")
  render json: { runs: [], error: e.message }, status: :unprocessable_entity
end

# ============================================================
# SECTION 01.60 — ACTION: steps_index
# ROUTE: GET /api/claims/ingest/runs/:ingest_run_id/steps
# PURPOSE:
# - Returns step rows (upload/di/genai) for a single ingest_run
# ============================================================

def steps_index
  ingest_run_id = params[:ingest_run_id].to_s.strip
  raise "Missing ingest_run_id in route." if ingest_run_id.empty?

  limit = params[:limit].to_i
  limit = 50 if limit <= 0
  limit = 200 if limit > 200

  scope = ::Claims::IngestStepRun.where(ingest_run_id: ingest_run_id).order(created_at: :desc)

  rows = scope.limit(limit).map do |r|
    {
      id: r.id,
      ingest_run_id: r.ingest_run_id,
      invoice_version_id: r.invoice_version_id,
      step_type: r.step_type,
      ok: r.ok,
      error_text: r.error_text,
      validationgenai_ruleset_id: r.respond_to?(:validationgenai_ruleset_id) ? r.validationgenai_ruleset_id : nil,
      created_at: r.created_at,
      updated_at: r.updated_at
    }
  end

  render json: { steps: rows }, status: :ok

rescue => e
  Rails.logger.error("[claims][ingest][steps_index] ERROR: #{e.class}: #{e.message}")
  render json: { steps: [], error: e.message }, status: :unprocessable_entity
end



# ============================================================
# SECTION 01.61 — ACTION: steps_by_session_index
# ROUTE: GET /api/claims/ingest/steps?session_id=<uuid>
# PURPOSE:
# - Returns ingest_step_runs filtered by session_id
# - Supports orphan/manual steps (ingest_run_id NULL) because session_id is on the table
# ============================================================

def steps_by_session_index
  session_id = params[:session_id].to_s.strip
  raise "Missing session_id in querystring." if session_id.empty?

  limit = params[:limit].to_i
  limit = 200 if limit <= 0
  limit = 500 if limit > 500

  scope = ::Claims::IngestStepRun.where(session_id: session_id).order(created_at: :desc)

  rows = scope.limit(limit).map do |r|
    {
      id: r.id,
      ingest_run_id: r.ingest_run_id,
      session_id: r.session_id,
      invoice_version_id: r.invoice_version_id,
      step_type: r.step_type,
      ok: r.ok,
      error_text: r.error_text,
      validationgenai_ruleset_id: r.respond_to?(:validationgenai_ruleset_id) ? r.validationgenai_ruleset_id : nil,
      created_at: r.created_at,
      updated_at: r.updated_at
    }
  end

  render json: { steps: rows }, status: :ok

rescue => e
  Rails.logger.error("[claims][ingest][steps_by_session_index] ERROR: #{e.class}: #{e.message}")
  render json: { steps: [], error: e.message }, status: :unprocessable_entity
end



      # ============================================================
      # SECTION 02 — ACTION: upload
      # ROUTE: POST /api/claims/sessions/:session_id/upload
      # PURPOSE:
      # - Accept multipart pdfs[] (or pdfs/files/file fallbacks)
      # - Call service Claims::Ingest::UploadPdfs
      # - Return run report JSON for GUI troubleshooting
      # ============================================================

      def upload

        # ============================================================
        # SECTION 02.01 — INPUT PARSING
        # ============================================================


        session_id = params[:session_id].to_s

        files =
          Array(params[:"pdfs[]"]) +
          Array(params[:pdfs]) +
          Array(params[:files]) +
          Array(params[:file])

        files = files.flatten.compact

        # ============================================================
        # SECTION 02.02 — SERVICE CALL
        # ============================================================


        result = ::Claims::Ingest::UploadPdfs.call(
          session_id: session_id,
          files: files
        )

        render json: result.to_h, status: :ok

      rescue => e
        Rails.logger.error("[claims][ingest][upload] ERROR: #{e.class}: #{e.message}")
        render json: {
          ok: false,
          stage: "upload_pdfs",
          error: e.message
        }, status: :unprocessable_entity
      end


# ============================================================
# SECTION 02.10 — ACTION: run_ocr
# ROUTE: POST /api/claims/ingest/run_ocr
# BODY: { invoice_version_id: "uuid", ingest_run_id?: "uuid" }
# PURPOSE:
# - enqueue Sidekiq job that calls Node /inv/ocr
# - creates ingest_step_runs row inside the job
# ============================================================
def run_ocr
  invoice_version_id = params[:invoice_version_id].to_s.strip
  raise "Missing invoice_version_id" if invoice_version_id.empty?

  ingest_run_id = params[:ingest_run_id].to_s.strip
  ingest_run_id = nil if ingest_run_id.empty?

  jid = ::Claims::RunOcrJob.perform_async(invoice_version_id, ingest_run_id)

  render json: {
    ok: true,
    enqueued: true,
    job_id: jid,
    invoice_version_id: invoice_version_id,
    ingest_run_id: ingest_run_id
  }, status: :ok

rescue => e
  Rails.logger.error("[claims][ingest][run_ocr] ERROR: #{e.class}: #{e.message}")
  render json: { ok: false, error: e.message }, status: :unprocessable_entity
end




    end
  end
end
