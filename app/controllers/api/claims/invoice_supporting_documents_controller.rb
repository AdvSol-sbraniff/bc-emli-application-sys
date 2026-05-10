require "json"
require "net/http"

module Api
  module Claims
    class InvoiceSupportingDocumentsController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!,
                         only: %i[context index create destroy pdf_url]
      skip_before_action :require_confirmation,
                         only: %i[context index create destroy pdf_url]
      skip_after_action :verify_authorized,
                        only: %i[context index create destroy pdf_url]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[context index create destroy pdf_url]

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

        rows =
          invoice
            .supporting_documents
            .order(created_at: :desc, id: :desc)
            .as_json(
              only: %i[
                id
                invoice_id
                storage_provider
                storage_key
                original_filename
                content_type
                byte_size
                sha256
                created_at
                updated_at
              ]
            )

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

      def create
        invoice = ::Claims::Invoice.find(params[:invoice_id])

        files =
          Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:files]) + Array(params[:file])

        result =
          ::Claims::SupportingDocuments::UploadPdfs.call(
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
          "[claims][invoice_supporting_documents][create] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
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
        node_resp =
          node_mint_sas!(
            storage_key: doc.storage_key,
            container: ENV["AZURE_BLOB_CONTAINER"]
          )
        render json: { sas_url: node_resp["sas_url"] }, status: :ok
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

      private

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
