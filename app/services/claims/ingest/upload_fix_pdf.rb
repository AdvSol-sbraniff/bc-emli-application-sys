require "net/http"
require "uri"
require "json"
require "securerandom"

module Claims
  module Ingest
    class UploadFixPdf
      Result =
        Struct.new(
          :ok,
          :stage,
          :invoice_id,
          :invoice_version_id,
          :invoice_versionno,
          :session_id,
          :ingest_run_id,
          :job_id,
          :status,
          :message,
          :error
        ) do
          def to_h
            {
              ok: ok,
              stage: stage,
              invoice_id: invoice_id,
              invoice_version_id: invoice_version_id,
              invoice_versionno: invoice_versionno,
              session_id: session_id,
              ingest_run_id: ingest_run_id,
              job_id: job_id,
              status: status,
              message: message,
              error: error
            }
          end
        end

      def self.call(invoice_id:, files:)
        new(invoice_id: invoice_id, files: files).call
      end

      def initialize(invoice_id:, files:)
        @invoice_id = invoice_id.to_s
        @files = Array(files).flatten.compact
      end

      def call
        stage = "upload_fix_pdf"
        raise "Missing invoice_id in route." if @invoice_id.strip.empty?

        invoice = ::Claims::Invoice.find_by(id: @invoice_id)
        unless invoice
          raise "Invalid invoice_id. No claims.invoices row exists for id=#{@invoice_id}"
        end

        if @files.empty?
          invoice.set_workflow_status!(
            "package_needs_correction",
            status_subtype: "package_missing_required_fix_file"
          )
          return(
            Result.new(
              false,
              stage,
              invoice.id,
              nil,
              nil,
              invoice.session_id,
              nil,
              nil,
              invoice.status,
              nil,
              "No corrected invoice file was provided."
            )
          )
        end
        if @files.size != 1
          invoice.set_workflow_status!(
            "package_needs_correction",
            status_subtype: "package_replacement_multiple_files"
          )
          return(
            Result.new(
              false,
              stage,
              invoice.id,
              nil,
              nil,
              invoice.session_id,
              nil,
              nil,
              invoice.status,
              nil,
              "Fix upload is single-file only. Received #{@files.size} file(s)."
            )
          )
        end

        file = @files.first
        name = safe_call(file, :original_filename) || "unknown.pdf"
        ctype = safe_call(file, :content_type) || "application/pdf"
        size = safe_call(file, :size)

        now = Time.zone.now
        invoice_version = nil
        ingest_run = nil
        attempts = 0

        begin
          ActiveRecord::Base.transaction do
            locked_invoice = ::Claims::Invoice.lock.find(invoice.id)
            next_versionno =
              ::Claims::InvoiceVersion
                .where(invoice_id: locked_invoice.id)
                .maximum(:invoice_versionno)
                .to_i + 1

            ingest_run =
              ::Claims::IngestRun.create!(
                session_id: locked_invoice.session_id,
                contractor_id: locked_invoice.contractor_id,
                status: "queued",
                total_files: 1,
                completed_files: 0,
                failed_files: 0,
                messages: [],
                created_at: now,
                updated_at: now
              )

            pending_key =
              "PENDING/session=#{locked_invoice.session_id}/invoice=#{locked_invoice.id}/v=#{next_versionno}/#{SecureRandom.uuid}.pdf"

            invoice_version =
              ::Claims::InvoiceVersion.create!(
                invoice_id: locked_invoice.id,
                invoice_versionno: next_versionno,
                storage_provider: "azure_blob",
                storage_key: pending_key,
                original_filename: name,
                content_type: ctype,
                byte_size: size,
                created_at: now,
                updated_at: now
              )

            locked_invoice.set_workflow_status_columns!(
              "upload_in_progress",
              now: now
            )
          end
        rescue ActiveRecord::RecordNotUnique
          attempts += 1
          retry if attempts < 3
          raise
        end

        node_resp =
          node_upload_pdf!(
            session_id: invoice.session_id,
            invoice_version_id: invoice_version.id,
            file: file
          )

        final_storage_key = extract_storage_key(node_resp)

        ActiveRecord::Base.transaction do
          locked_invoice = ::Claims::Invoice.lock.find(invoice.id)
          locked_version =
            ::Claims::InvoiceVersion.lock.find(invoice_version.id)

          if final_storage_key.to_s.strip.empty?
            locked_invoice.set_workflow_status_columns!(
              "technical_failure",
              status_subtype: "upload_storage_key_missing",
              now: Time.zone.now
            )

            return(
              Result.new(
                false,
                stage,
                invoice.id,
                invoice_version.id,
                invoice_version.invoice_versionno,
                invoice.session_id,
                ingest_run&.id,
                nil,
                ingest_run&.status,
                nil,
                "Node upload returned no storage_key"
              )
            )
          end

          version_updates = {
            storage_key: final_storage_key,
            updated_at: Time.zone.now
          }
          version_updates[:byte_size] = node_resp[
            "byte_size"
          ] if node_resp.key?("byte_size")
          version_updates[:sha256] = node_resp["sha256"] if node_resp.key?(
            "sha256"
          )

          locked_version.update_columns(version_updates)

          locked_invoice.set_workflow_status_columns!(
            "ocr_queued",
            now: Time.zone.now
          )

          ::Claims::IngestStepRun.create!(
            ingest_run_id: ingest_run.id,
            session_id: locked_invoice.session_id,
            invoice_version_id: locked_version.id,
            step_type: "plus1fix_ocr_read",
            status: "queued",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )
        end

        job_id =
          ::Claims::RunInvoiceVersionClassifierJob.perform_async(
            invoice_version.id,
            ingest_run.id
          )

        ::Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run.id)
        ingest_run.reload

        Result.new(
          true,
          stage,
          invoice.id,
          invoice_version.id,
          invoice_version.invoice_versionno,
          invoice.session_id,
          ingest_run.id,
          job_id,
          ingest_run.status,
          "Upload fix accepted. Classifier, OCR, and GenAI have been queued for the new invoice version.",
          nil
        )
      rescue => e
        begin
          if ingest_run&.id && invoice_version&.id
            ::Claims::IngestStepRun.create!(
              ingest_run_id: ingest_run.id,
              session_id: invoice&.session_id,
              invoice_version_id: invoice_version.id,
              step_type: "ocr_invoice",
              status: "failed",
              error_text: "upload_fix_failed: #{e.message}",
              created_at: Time.current,
              updated_at: Time.current
            )
            ::Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run.id)
          end
          invoice&.set_workflow_status!(
            "technical_failure",
            status_subtype: upload_fix_failure_subtype(e)
          )
        rescue StandardError
          # best-effort failure tracking only
        end

        Result.new(
          false,
          stage,
          invoice&.id,
          invoice_version&.id,
          invoice_version&.invoice_versionno,
          invoice&.session_id,
          ingest_run&.id,
          nil,
          ingest_run&.reload&.status,
          nil,
          "#{e.class}: #{e.message}"
        )
      end

      private

      def safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)
        obj.public_send(method_name)
      rescue StandardError
        nil
      end

      def node_upload_pdf!(session_id:, invoice_version_id:, file:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        base = base.sub(%r{/\z}, "")
        uri = URI("#{base}/inv/upload-pdf")

        req = Net::HTTP::Post.new(uri)

        io = File.open(file.path, "rb")
        filename =
          safe_call(file, :original_filename) || File.basename(file.path)
        content_type = safe_call(file, :content_type) || "application/pdf"

        form = [
          ["sessionId", session_id.to_s],
          ["invoiceVersionId", invoice_version_id.to_s],
          ["file", io, { filename: filename, content_type: content_type }]
        ]

        req.set_form(form, "multipart/form-data")

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Node upload failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      ensure
        io&.close
      end

      def extract_storage_key(node_resp)
        node_resp.fetch("storage_key")
      end

      def upload_fix_failure_subtype(error)
        message = error.message.to_s.downcase
        return "upload_service_error" if message.include?("node upload failed")
        if error.is_a?(JSON::ParserError)
          return "upload_service_malformed_response"
        end
        return "upload_storage_key_missing" if message.include?("storage_key")

        "upload_unexpected_exception"
      end
    end
  end
end
