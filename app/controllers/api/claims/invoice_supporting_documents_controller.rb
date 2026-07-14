require "json"
require "net/http"

module Api
  module Claims
    class InvoiceSupportingDocumentsController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!,
                         only: %i[context index destroy pdf_url pdf]
      skip_before_action :require_confirmation,
                         only: %i[context index destroy pdf_url pdf]
      skip_after_action :verify_authorized,
                        only: %i[context index destroy pdf_url pdf]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[context index destroy pdf_url pdf]

      def context
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        grid_row = ::Claims::InvoiceGrid.find_by(invoice_id: invoice.id)
        latest_version =
          ::Claims::InvoiceVersion
            .where(invoice_id: invoice.id)
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .first

        render json: {
                 invoice_id: invoice.id,
                 session_id: invoice.session_id,
                 session_created_at: grid_row&.session_created_at,
                 contractor_business_name: grid_row&.contractor_business_name,
                 invoice_created_at: invoice.created_at,
                 latest_invoice_version_id: latest_version&.id,
                 latest_ocr_invoice_number: latest_version&.di_ocr_invoice_id
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][invoice_supporting_documents][context] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def index
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        latest_version =
          ::Claims::InvoiceVersion
            .where(invoice_id: invoice.id)
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .first
        if latest_version.nil?
          render json: { rows: [] }, status: :ok
          return
        end

        rows =
          latest_version
            .supporting_documents
            .includes(
              :supporting_document_type,
              :supporting_document_located_fields,
              :supporting_document_visual_findings
            )
            .order(created_at: :desc, id: :desc)
            .map { |row| serialize_supporting_document(row) }

        render json: { rows: rows }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "Invoice not found",
                 rows: []
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][invoice_supporting_documents][index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      def destroy
        doc = ::Claims::SupportingDocument.find(params[:id])
        node_delete_blob!(
          storage_key: doc.storage_key,
          container: ENV["AZURE_BLOB_CONTAINER"]
        )
        doc.destroy!

        render json: { ok: true, deleted_id: params[:id] }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 ok: false,
                 error: "Supporting document not found"
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][invoice_supporting_documents][destroy] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      def pdf_url
        doc = ::Claims::SupportingDocument.find(params[:id])
        render json: {
                 sas_url:
                   node_mint_sas!(
                     storage_key: doc.storage_key,
                     container: ENV["AZURE_BLOB_CONTAINER"].presence
                   ).fetch("sas_url")
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "Supporting document not found"
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][invoice_supporting_documents][pdf_url] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def pdf
        doc = ::Claims::SupportingDocument.find(params[:id])
        stream_blob_pdf!(storage_key: doc.storage_key)
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "Supporting document not found"
               },
               status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][invoice_supporting_documents][pdf] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def stream_blob_pdf!(storage_key:, container: ENV["AZURE_BLOB_CONTAINER"])
        res =
          node_download_blob!(storage_key: storage_key, container: container)
        send_data res.body,
                  type: res["content-type"].presence || "application/pdf",
                  disposition: "inline",
                  filename:
                    File.basename(storage_key.to_s.presence || "document.pdf")
      end

      def serialize_supporting_document(row)
        display_type =
          row.supporting_document_type&.description ||
            row.supporting_document_type&.type_key || row.content_type

        {
          id: row.id,
          invoice_version_id: row.invoice_version_id,
          supporting_document_type_id: row.supporting_document_type_id,
          supporting_document_type_key: row.supporting_document_type&.type_key,
          supporting_document_type_description:
            row.supporting_document_type&.description,
          classification_status: row.classification_status,
          classification_confidence: row.classification_confidence,
          classification_reason: row.classification_reason,
          supporting_document_routing_quality:
            row.supporting_document_routing_quality,
          supporting_document_routing_quality_reason:
            row.supporting_document_routing_quality_reason,
          located_fields: serialize_located_fields(row),
          visual_findings: serialize_visual_findings(row),
          classified_at: row.classified_at,
          storage_provider: row.storage_provider,
          storage_key: row.storage_key,
          original_filename: row.original_filename,
          content_type: display_type,
          mime_content_type: row.content_type,
          byte_size: row.byte_size,
          sha256: row.sha256,
          created_at: row.created_at,
          updated_at: row.updated_at
        }
      end

      def serialize_located_fields(row)
        row
          .supporting_document_located_fields
          .includes(:supporting_document_type_located_field)
          .order(:field_key, :created_at)
          .map do |field|
            definition = field.supporting_document_type_located_field
            field.as_json(
              only: %i[
                id
                supporting_document_id
                supporting_document_type_located_field_id
                source_engine
                field_key
                value_type
                value_text
                value_json
                confidence
                page
                polygon
                evidence_text
                created_at
                updated_at
              ]
            ).merge(
              "field_number" => definition&.field_number,
              "contractor_display_name" => definition&.contractor_display_name,
              "prompt_text" => definition&.prompt_text
            )
          end
      end

      def serialize_visual_findings(row)
        row
          .supporting_document_visual_findings
          .order(:finding_seqno, :created_at)
          .map do |finding|
            finding.as_json(
              only: %i[
                id
                supporting_document_id
                finding_seqno
                source_engine
                finding_type
                page
                summary
                legibility
                confidence
                raw_json
                created_at
                updated_at
              ]
            )
          end
      end

      def node_mint_sas!(storage_key:, container: nil)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/mint-sas")
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
          raise "Node mint-sas failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      end

      def node_download_blob!(storage_key:, container: nil)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/download-blob")
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

        unless res.is_a?(Net::HTTPSuccess)
          raise "Node download-blob failed HTTP=#{res.code} body=#{res.body}"
        end

        res
      end

      def node_delete_blob!(storage_key:, container: nil)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/delete-blob")
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
          raise "Node delete-blob failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      end
    end
  end
end
