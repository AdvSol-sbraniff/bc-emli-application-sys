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


      skip_before_action :authenticate_user!, only: %i[upload]
      skip_before_action :require_confirmation, only: %i[upload]
      skip_after_action  :verify_authorized,   only: %i[upload]
      skip_forgery_protection only: %i[upload]

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

      # ============================================================
      # SECTION 99 — ERROR HANDLING
      # ============================================================


      rescue => e
        Rails.logger.error("[claims][ingest][upload] ERROR: #{e.class}: #{e.message}")
        render json: {
          ok: false,
          stage: "upload_pdfs",
          error: e.message
        }, status: :unprocessable_entity
      end
    end
  end
end
