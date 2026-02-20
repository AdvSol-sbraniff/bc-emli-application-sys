# app/services/claims/ingest/upload_pdfs.rb

# ============================================================
# SECTION 00 — FILE OVERVIEW
# PURPOSE: POC upload step for Claims ingest
# CURRENT BEHAVIOUR:
# - DB-only step (no Azure calls yet)
# - Creates: invoices, invoice_versions
# - Creates run tracking rows: ingest_runs + ingest_step_runs(step_type='upload')
# - Returns a "run report" with messages + per-file results[]
# ============================================================


require "net/http"
require "uri"
require "json"

require "securerandom"

module Claims
  module Ingest
    class UploadPdfs

      # ============================================================
      # SECTION 01 — RESULT SHAPE
      # PURPOSE: Stable JSON contract back to React "Run Output" panel.
      # ============================================================

      Result = Struct.new(
        :ok,
        :stage,
        :run_id,

        # NEW: run tracker id (claims.ingest_runs.id)
        :ingest_run_id,

        :session_id,

        # convenience ids for the UI (first successful file)
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

            ingest_run_id: ingest_run_id,

            session_id: session_id,
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
      # ============================================================

      def self.call(session_id:, files:)
        new(session_id: session_id, files: files).call
      end

      # ============================================================
      # SECTION 03 — INIT
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

        # SINGLE FILE ONLY (admin tool)
        if @files.size != 1
          raise "New upload is single-file only. Received #{@files.size} file(s)."
        end

ingest_run = nil  # manual tool: no parent ingest_runs row


        # ============================================================
        # SECTION 04.02 — RUN CONTEXT / START LOGGING
        # ============================================================

Rails.logger.info("[claims][ingest][#{stage}] run_id=#{run_id} ingest_run_id=nil session_id=#{@session_id} files=#{@files.size}")

        msgs << "Step1 DB-only: creating invoices + invoice_versions (no Azure yet)."
        msgs << "run_id=#{run_id}"
        msgs << "ingest_run_id=nil"
        msgs << "session_id=#{@session_id}"
        msgs << "received_files=#{@files.size}"

        # ============================================================
        # SECTION 04.03 — SINGLE FILE ONLY (NO LOOP)
        # ============================================================

        f = @files.first
        name = safe_call(f, :original_filename) || "unknown.pdf"
        ctype = safe_call(f, :content_type) || "application/pdf"
        size = safe_call(f, :size)
Rails.logger.info("[claims][ingest][#{stage}] run_id=#{run_id} ingest_run_id=nil file1=#{name} type=#{ctype} size=#{size}")

        begin
          rec = nil

          # ============================================================
          # SECTION 04.03.01 — DB TRANSACTION
          # CREATES: invoices, invoice_versions, ingest_step_runs(type=upload)
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

            # 3) ingest_step_runs (type=upload)
            # NOTE: this table is your unified runs table (upload/di/genai) with nullable fields.

            

            rec = {
              file_index: 1,
              original_filename: name,
              content_type: ctype,
              byte_size: size,
              status: "created_db_rows_only",
              invoice_id: invoice.id,
              invoice_version_id: invoice_version.id,
              storage_key: pending_key
            }
          end

          results << rec

          first_invoice_id = rec[:invoice_id]
          first_invoice_version_id = rec[:invoice_version_id]

          msgs << "file1: OK — created invoice=#{rec[:invoice_id]} version=#{rec[:invoice_version_id]} (step_run type=upload)"

# ============================================================
# SECTION 04.03.02 — CALL NODE (UPLOAD) + FINALIZE DB
# ============================================================

node_resp = node_upload_pdf!(
  session_id: @session_id,
  invoice_version_id: rec[:invoice_version_id],
  file: f
)

final_storage_key = extract_storage_key(node_resp)

ActiveRecord::Base.transaction do
  inv = ::Claims::Invoice.lock.find(rec[:invoice_id])
  iv  = ::Claims::InvoiceVersion.lock.find(rec[:invoice_version_id])

  if final_storage_key.to_s.strip.empty?
    inv.update_columns(
      status: "upload_failed",
      status_updated_at: Time.zone.now,
      updated_at: Time.zone.now
    )

    rec[:status] = "upload_failed"
    rec[:node_response] = node_resp
    msgs << "file1: upload FAILED — Node returned no storage_key"
  else
# ============================================================
# SECTION 04.03.02.10 — UPDATE invoice_versions FROM NODE RESULT
# PURPOSE:
# - Persist final blob storage_key (replaces PENDING key)
# - Optionally persist upload metadata returned by Node (sha256/etag/etc)
# NOTES:
# - Keep this tolerant: only set fields if Node returned them
# - If a column doesn’t exist in DB yet, remove that line (or add the column later)
# ============================================================

iv_update = {
  storage_key: final_storage_key,
  updated_at: Time.zone.now
}

# ============================================================
# SECTION 04.03.02.11 — OPTIONAL METADATA (ONLY IF PROVIDED)
# ============================================================

iv_update[:byte_size] = node_resp["byte_size"] if node_resp.key?("byte_size")
iv_update[:sha256]    = node_resp["sha256"]    if node_resp.key?("sha256")
#iv_update[:etag]      = node_resp["etag"]      if node_resp.key?("etag")
#iv_update[:container] = node_resp["container"] if node_resp.key?("container")

# ============================================================
# SECTION 04.03.02.12 — APPLY UPDATE (LOCKED ROW)
# ============================================================
iv.update_columns(iv_update)

    inv.update_columns(
      status: "upload_complete",
      status_updated_at: Time.zone.now,
      updated_at: Time.zone.now
    )

    rec[:status] = "upload_complete"
    rec[:storage_key] = final_storage_key
    rec[:node_response] = node_resp
    msgs << "file1: upload OK — status=upload_complete storage_key=#{final_storage_key}"
  end
end



        rescue => e
Rails.logger.error("[claims][ingest][#{stage}] run_id=#{run_id} ingest_run_id=nil file1 FAILED: #{e.class}: #{e.message}")

          results << {
            file_index: 1,
            original_filename: name,
            content_type: ctype,
            byte_size: size,
            status: "failed",
            error: "#{e.class}: #{e.message}"
          }

          msgs << "file1: FAILED — #{e.class}: #{e.message}"
        end

        # ============================================================
        # SECTION 04.04 — SUMMARY + FINALIZE INGEST_RUN
        # ============================================================

ok = results.any? { |r| r[:status] == "upload_complete" }
uploaded_count = results.count { |r| r[:status] == "upload_complete" }
failed_count = results.size - uploaded_count


        msgs << "summary: created_db_rows_only=#{uploaded_count} failed=#{failed_count}"
        msgs << "next_step_hint: implement Azure upload then update invoice/status + set ingest_step_runs.error_text on failure."

Result.new(
  ok,
  stage,
  run_id,
  nil, # ingest_run_id (manual tool)
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

      # ============================================================
      # SECTION 90.01 — safe call HELPERS
      # ============================================================

      def safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)
        obj.public_send(method_name)
      rescue
        nil
      end

      # ============================================================
      # SECTION 90.02 node upload pdf helper
      # ============================================================

def node_upload_pdf!(session_id:, invoice_version_id:, file:)
  base = ENV["INV_NODE_BASE_URL"].to_s.strip
  raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

  base = base.sub(%r{/\z}, "")
  uri = URI("#{base}/inv/upload-pdf")

  req = Net::HTTP::Post.new(uri)

# Rails upload is a Tempfile on the SERVER/container; file.path is valid here
io = File.open(file.path, "rb")

filename = safe_call(file, :original_filename) || File.basename(file.path)
content_type = safe_call(file, :content_type) || "application/pdf"

form = [
  ["sessionId", session_id.to_s],
  ["invoiceVersionId", invoice_version_id.to_s],
  ["file", io, { filename: filename, content_type: content_type }]
]

req.set_form(form, "multipart/form-data")


  res = Net::HTTP.start(
    uri.host,
    uri.port,
    use_ssl: (uri.scheme == "https"),
    read_timeout: 120
  ) { |http| http.request(req) }

  body = res.body.to_s
  raise "Node upload failed HTTP=#{res.code} body=#{body}" unless res.is_a?(Net::HTTPSuccess)

  JSON.parse(body)
ensure
  io&.close
end

def extract_storage_key(node_resp)
  node_resp.fetch("storage_key")
end






    end
  end
end
