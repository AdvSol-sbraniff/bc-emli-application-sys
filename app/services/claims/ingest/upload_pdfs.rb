# app/services/claims/ingest/upload_pdfs.rb

# ============================================================
# SECTION 00 — FILE OVERVIEW
# PURPOSE: POC upload step for Claims ingest
# CURRENT BEHAVIOUR:
# - DB-only step (no Azure calls yet)
# - Creates: invoices, invoice_versions, upload_runs
# - Returns a "run report" with messages + per-file results[]
# ============================================================


require "securerandom"

module Claims
  module Ingest
    class UploadPdfs

      # ============================================================
      # SECTION 01 — RESULT SHAPE
      # PURPOSE: Stable JSON contract back to React "Run Output" panel.
      # ============================================================


      # ============================================================
      # SECTION 01 — RESULT SHAPE
      # PURPOSE: Stable JSON contract back to React "Run Output" panel.
      # ============================================================

      Result = Struct.new(
        :ok,
        :stage,
        :run_id,
        :session_id,

        # NEW: convenience ids for the UI (first successful file)
        :invoice_id,
        :invoice_version_id,

        :uploaded_count,
        :messages,
        :results
      ) do
        def to_h
          {
            ok: ok,
            stage: stage,
            run_id: run_id,
            session_id: session_id,

            # NEW
            invoice_id: invoice_id,
            invoice_version_id: invoice_version_id,

            uploaded_count: uploaded_count,
            messages: messages,
            results: results
          }
        end
      end


      # ============================================================
      # SECTION 02 — ENTRYPOINT
      # PURPOSE: Conventional service call wrapper.
      # ============================================================


      def self.call(session_id:, files:)
        new(session_id: session_id, files: files).call
      end

      # ============================================================
      # SECTION 03 — INIT
      # PURPOSE: Normalize inputs.
      # ============================================================


      def initialize(session_id:, files:)
        @session_id = session_id.to_s
        @files = Array(files).flatten.compact
      end

      # ============================================================
      # SECTION 04 — MAIN EXECUTION
      # ============================================================


      def call
        run_id = SecureRandom.uuid
        stage = "upload_pdfs"
        msgs = []

        # convenience ids for GUI (first success)
        first_invoice_id = nil
        first_invoice_version_id = nil


        results = []
        now = Time.zone.now

        # ============================================================
        # SECTION 04.01 — INPUT VALIDATION
        # ============================================================


        raise "Missing session_id in route." if @session_id.strip.empty?
unless ::Claims::Session.exists?(id: @session_id)
  raise "Invalid session_id. No claims.sessions row exists for id=#{@session_id}"
end
        raise "No files received. Expected multipart field pdfs[] (or pdfs)." if @files.empty?

        # ============================================================
        # SECTION 04.02 — RUN CONTEXT / START LOGGING
        # ============================================================


        Rails.logger.info("[claims][ingest][#{stage}] run_id=#{run_id} session_id=#{@session_id} files=#{@files.size}")

        msgs << "Step1 DB-only: creating invoices + invoice_versions + upload_runs (no Azure yet)."
        msgs << "run_id=#{run_id}"
        msgs << "session_id=#{@session_id}"
        msgs << "received_files=#{@files.size}"

        # ============================================================
        # SECTION 04.03 — PER-FILE LOOP
        # PURPOSE: For each file, create DB rows inside a transaction.
        # ============================================================


        @files.each_with_index do |f, idx|
          name = safe_call(f, :original_filename) || "unknown.pdf"
          ctype = safe_call(f, :content_type) || "application/pdf"
          size = safe_call(f, :size)

          Rails.logger.info("[claims][ingest][#{stage}] run_id=#{run_id} file#{idx + 1}=#{name} type=#{ctype} size=#{size}")

          begin
            rec = nil

            # ============================================================
            # SECTION 04.03.01 — DB TRANSACTION
            # CREATES: invoices, invoice_versions, upload_runs
            # ============================================================


            ActiveRecord::Base.transaction do
              # 1) invoices
              invoice = ::Claims::Invoice.create!(
                session_id: @session_id,
                status: "upload_in_progress",
                status_updated_at: now,
                created_at: now,
                updated_at: now
              )

              # 2) invoice_versions (v1)
              # storage_key is NOT NULL, so we write a deterministic placeholder for now.
              pending_key = "PENDING/session=#{@session_id}/invoice=#{invoice.id}/v=1/#{SecureRandom.uuid}.pdf"

              invoice_version = ::Claims::InvoiceVersion.create!(
                invoice_id: invoice.id,
                invoice_versionno: 1,

                storage_provider: "azure_blob",
                storage_key: pending_key,
                original_filename: name,
                content_type: ctype,
                byte_size: size,

                created_at: now,
                updated_at: now
              )

              # 3) upload_runs
              upload_run = ::Claims::UploadRun.create!(
                invoice_version_id: invoice_version.id,
                error_text: nil,
                created_at: now,
                updated_at: now
              )

              # (Optional) if you want invoice.status to remain “upload_in_progress” until Azure is done,
              # keep as-is. Later you’ll set “upload_failed” / move to “ocr_in_progress”.

              rec = {
                file_index: idx + 1,
                original_filename: name,
                content_type: ctype,
                byte_size: size,
                status: "created_db_rows_only",
                invoice_id: invoice.id,
                invoice_version_id: invoice_version.id,
                upload_run_id: upload_run.id,
                storage_key: pending_key
              }
            end

            results << rec

            # capture first successful ids for top-level UI fields
            first_invoice_id ||= rec[:invoice_id]
            first_invoice_version_id ||= rec[:invoice_version_id]


            msgs << "file#{idx + 1}: OK — created invoice=#{rec[:invoice_id]} version=#{rec[:invoice_version_id]} upload_run=#{rec[:upload_run_id]}"
          rescue => e
            Rails.logger.error("[claims][ingest][#{stage}] run_id=#{run_id} file#{idx + 1} FAILED: #{e.class}: #{e.message}")

            results << {
              file_index: idx + 1,
              original_filename: name,
              content_type: ctype,
              byte_size: size,
              status: "failed",
              error: "#{e.class}: #{e.message}"
            }

            msgs << "file#{idx + 1}: FAILED — #{e.class}: #{e.message}"
            # continue to next file (multi-file upload should partially succeed for POC)
          end
        end

        # ============================================================
        # SECTION 04.04 — SUMMARY + RETURN
        # ============================================================


        ok = results.any? { |r| r[:status] == "created_db_rows_only" }
        uploaded_count = results.count { |r| r[:status] == "created_db_rows_only" }

        msgs << "summary: created_db_rows_only=#{uploaded_count} failed=#{results.size - uploaded_count}"
        msgs << "next_step_hint: implement Azure upload then update invoice/status + upload_runs.error_text on failure."
     
        Result.new(
          ok,
          stage,
          run_id,
          @session_id,
          first_invoice_id,
          first_invoice_version_id,
          uploaded_count,
          msgs,
          results
        )


      end

      # ============================================================
      # SECTION 90 — PRIVATE HELPERS
      # ============================================================


      private

      def safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)
        obj.public_send(method_name)
      rescue
        nil
      end
    end
  end
end
