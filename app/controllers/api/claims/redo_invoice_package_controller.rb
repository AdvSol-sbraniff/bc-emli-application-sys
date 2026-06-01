require "json"
require "net/http"

module Api
  module Claims
    class RedoInvoicePackageController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!,
                         only: %i[context documents create destroy pdf_url redo]
      skip_before_action :require_confirmation,
                         only: %i[context documents create destroy pdf_url redo]
      skip_after_action :verify_authorized,
                        only: %i[context documents create destroy pdf_url redo]
      skip_after_action :verify_policy_scoped, only: %i[documents]
      skip_forgery_protection only: %i[
                                context
                                documents
                                create
                                destroy
                                pdf_url
                                redo
                              ]

      def context
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        grid_row = ::Claims::InvoiceGrid.find_by(invoice_id: invoice.id)
        latest_version = latest_invoice_version(invoice.id)

        render json: {
                 invoice_id: invoice.id,
                 session_id: invoice.session_id,
                 status: invoice.status,
                 session_created_at: grid_row&.session_created_at,
                 contractor_business_name: grid_row&.contractor_business_name,
                 latest_invoice_version_id: latest_version&.id,
                 latest_invoice_versionno: latest_version&.invoice_versionno,
                 latest_original_filename: latest_version&.original_filename,
                 latest_ocr_invoice_number: latest_version&.di_ocr_invoice_id
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][redo_invoice_package][context] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def documents
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        rows =
          ::Claims::IngestDocument
            .where(
              "invoice_id = :invoice_id OR resolved_invoice_id = :invoice_id",
              invoice_id: invoice.id
            )
            .includes(:supporting_document_type)
            .order(created_at: :desc, id: :desc)
            .map { |row| serialize_document(row) }

        render json: { rows: rows }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "Invoice not found",
                 rows: []
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][redo_invoice_package][documents] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      def create
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        files =
          Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:files]) + Array(params[:file])

        result =
          ::Claims::Ingest::UploadRedoPackageDocuments.call(
            invoice_id: invoice.id,
            files: files
          )
        render json: result, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 ok: false,
                 error: "Invoice not found"
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][redo_invoice_package][create] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      def redo
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        validationgenai_ruleset_id =
          params[:validationgenai_ruleset_id].to_s.strip.presence

        result =
          ::Claims::Ingest::RedoInvoicePackage.call(
            invoice_id: invoice.id,
            validationgenai_ruleset_id: validationgenai_ruleset_id
          )
        render json: result, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 ok: false,
                 error: "Invoice not found"
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][redo_invoice_package][redo] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      def destroy
        document = ::Claims::IngestDocument.find(params[:id])
        if document.promoted_supporting_document_id.present? ||
             document.resolved_invoice_version_id.present?
          raise "Cannot delete a package PDF that has already been promoted."
        end

        storage_key = document.storage_key
        document.destroy!

        if delete_blob_safe?(storage_key)
          node_delete_blob!(
            storage_key: storage_key,
            container: ENV["AZURE_BLOB_CONTAINER"]
          )
        end

        render json: { ok: true, deleted_id: params[:id] }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 ok: false,
                 error: "Package PDF not found"
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][redo_invoice_package][destroy] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      def pdf_url
        document = ::Claims::IngestDocument.find(params[:id])
        node_resp =
          node_mint_sas!(
            storage_key: document.storage_key,
            container: ENV["AZURE_BLOB_CONTAINER"]
          )
        render json: { sas_url: node_resp["sas_url"] }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Package PDF not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][redo_invoice_package][pdf_url] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def latest_invoice_version(invoice_id)
        ::Claims::InvoiceVersion
          .where(invoice_id: invoice_id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .first
      end

      def serialize_document(row)
        latest_steps = latest_steps_for(row.id)
        {
          id: row.id,
          ingest_run_id: row.ingest_run_id,
          invoice_id: row.invoice_id || row.resolved_invoice_id,
          resolved_invoice_id: row.resolved_invoice_id,
          resolved_invoice_version_id: row.resolved_invoice_version_id,
          promoted_supporting_document_id: row.promoted_supporting_document_id,
          original_filename: row.original_filename,
          content_type: row.content_type,
          byte_size: row.byte_size,
          storage_provider: row.storage_provider,
          storage_key: row.storage_key,
          document_kind: row.document_kind,
          document_kind_confidence: row.document_kind_confidence,
          document_kind_reason: row.document_kind_reason,
          supporting_document_type_key: row.supporting_document_type&.type_key,
          supporting_document_type_description:
            row.supporting_document_type&.description,
          classification_status: row.classification_status,
          classification_confidence: row.classification_confidence,
          classification_reason: row.classification_reason,
          supplement_routing_quality: row.supplement_routing_quality,
          supplement_routing_quality_reason:
            row.supplement_routing_quality_reason,
          has_di_read: row.di_read_raw_json.present?,
          has_classifier: row.classifier_raw_json.present?,
          latest_steps: latest_steps,
          created_at: row.created_at,
          updated_at: row.updated_at
        }
      end

      def latest_steps_for(ingest_document_id)
        ::Claims::IngestStepRun
          .where(ingest_document_id: ingest_document_id)
          .order(created_at: :desc)
          .to_a
          .group_by(&:step_type)
          .transform_values(&:first)
          .transform_values do |step|
            {
              id: step.id,
              step_type: step.step_type,
              status: step.status,
              error_text: step.error_text,
              created_at: step.created_at,
              updated_at: step.updated_at
            }
          end
      end

      def delete_blob_safe?(storage_key)
        return false if storage_key.blank?

        invoice_version_count =
          ::Claims::InvoiceVersion.where(storage_key: storage_key).count
        supporting_document_count =
          ::Claims::SupportingDocument.where(storage_key: storage_key).count
        ingest_document_count =
          ::Claims::IngestDocument.where(storage_key: storage_key).count

        invoice_version_count.zero? && supporting_document_count.zero? &&
          ingest_document_count.zero?
      end

      def node_mint_sas!(storage_key:, container: nil)
        node_blob_request!(
          path: "/inv/mint-sas",
          storage_key: storage_key,
          container: container
        )
      end

      def node_delete_blob!(storage_key:, container: nil)
        node_blob_request!(
          path: "/inv/delete-blob",
          storage_key: storage_key,
          container: container
        )
      end

      def node_blob_request!(path:, storage_key:, container: nil)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}#{path}")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = {
          storageKey: storage_key,
          container: container
        }.compact.to_json

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 60
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Node #{path} failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      end
    end
  end
end
