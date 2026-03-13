# frozen_string_literal: true

module Api
  module Claims
    class RevisionRequestsAdminController < ApplicationController
      skip_before_action :authenticate_user!, only: %i[index show create update destroy]
      skip_before_action :require_confirmation, only: %i[index show create update destroy]
      skip_after_action :verify_authorized, only: %i[index show create update destroy]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index show create update destroy]

      # GET /api/claims/admin/revision_requests
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        revision_status = params[:revision_request_status].to_s.strip
        session_id = params[:session_id].to_s.strip
        invoice_id = params[:invoice_id].to_s.strip
        sort = params[:sort].to_s.strip.presence || "revision_request_updated_at:desc"

        scope = ::Claims::RevisionRequestGrid.all

        scope = scope.where(session_id: session_id) if session_id.present?
        scope = scope.where(invoice_id: invoice_id) if invoice_id.present?
        scope = scope.where(revision_request_status: revision_status) if revision_status.present?

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(
            <<~SQL.squish,
              CAST(claims.v_revision_request_grid.session_id AS text) ILIKE :like
              OR CAST(claims.v_revision_request_grid.invoice_id AS text) ILIKE :like
              OR CAST(claims.v_revision_request_grid.invoice_version_id AS text) ILIKE :like
              OR CAST(claims.v_revision_request_grid.revision_request_id AS text) ILIKE :like
              OR claims.v_revision_request_grid.revision_request_status ILIKE :like
              OR claims.v_revision_request_grid.revision_request_text ILIKE :like
              OR claims.v_revision_request_grid.revision_request_response_text ILIKE :like
            SQL
            like: like
          )
        end

        scope = scope.order(order_clause(sort))

        total = scope.count
        rows = scope.offset((page - 1) * per).limit(per)
        rows_json = rows.as_json

        invoice_ids = rows_json.map { |r| r["invoice_id"] }.compact.uniq
        contractor_by_invoice = {}

        if invoice_ids.any?
          contractor_by_invoice = ::Claims::InvoiceGrid
            .where(invoice_id: invoice_ids)
            .pluck(:invoice_id, :contractor_business_name)
            .to_h
        end

        rows_json.each do |r|
          r["contractor_business_name"] = contractor_by_invoice[r["invoice_id"]]
        end

        render json: {
          rows: rows_json,
          meta: {
            total: total,
            page: page,
            per: per,
            sort: sort,
            filters: {
              q: q.presence,
              revision_request_status: revision_status.presence,
              session_id: session_id.presence,
              invoice_id: invoice_id.presence
            }
          }
        }, status: :ok
      rescue => e
        Rails.logger.error("[CLAIMS][REVISION_REQUEST_GRID] ERROR: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /api/claims/admin/revision_requests/:id
      def show
        record = ::Claims::AdminRevisionRequest.find(params[:id])
        context = context_from_grid(record)
        render json: serialize_record(record).merge(context), status: :ok
      end

      # POST /api/claims/admin/revision_requests
      def create
        attempts = 0

        begin
          record = ::Claims::AdminRevisionRequest.new(create_params)
          record.save!
        rescue ActiveRecord::RecordNotUnique => e
          attempts += 1
          retry if attempts < 3
          raise e
        end

        render json: serialize_record(record), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      rescue ActiveRecord::NotNullViolation, ActiveRecord::StatementInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # PATCH /api/claims/admin/revision_requests/:id
      def update
        record = ::Claims::AdminRevisionRequest.find(params[:id])
        record.update!(update_params)

        render json: serialize_record(record), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      # DELETE /api/claims/admin/revision_requests/:id
      def destroy
        record = ::Claims::AdminRevisionRequest.find(params[:id])
        record.destroy!

        render json: { id: record.id, deleted: true }, status: :ok
      end

      private

      def create_params
        params.permit(
          :invoice_version_id,
          :requester_id,
          :status,
          :request_text,
          :response_text,
          :closed_at
        )
      end

      def update_params
        params.permit(:status, :request_text, :response_text, :closed_at)
      end

      def serialize_record(record)
        {
          id: record.id,
          invoice_version_id: record.invoice_version_id,
          revreq_seqno: record.revreq_seqno,
          requester_id: record.requester_id,
          status: record.status,
          request_text: record.request_text,
          response_text: record.response_text,
          closed_at: record.closed_at,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      end

      def context_from_grid(record)
        row = ::Claims::RevisionRequestGrid
          .where(revision_request_id: record.id)
          .order(Arel.sql("revision_request_updated_at DESC NULLS LAST"))
          .first

        return {} unless row

        contractor_name = nil
        if row.invoice_id.present?
          contractor_name = ::Claims::InvoiceGrid.where(invoice_id: row.invoice_id).limit(1).pluck(:contractor_business_name).first
        end

        {
          session_id: row.session_id,
          session_created_at: row.session_created_at,
          invoice_id: row.invoice_id,
          contractor_business_name: contractor_name,
          invoice_version_created_at: row.invoice_version_created_at,
          invoice_versionno: row.invoice_versionno,
          di_ocr_invoice_id: row.di_ocr_invoice_id
        }
      end

      def clamp_int(value, default, min, max)
        n = Integer(value) rescue default
        n = default if n.nil?
        n = min if n < min
        n = max if n > max
        n
      end

      def sanitize_sql_like(string)
        string.to_s.gsub(/[\\%_]/) { |x| "\\#{x}" }
      end

      def order_clause(sort)
        key, dir = sort.to_s.split(":", 2)
        dir = dir&.downcase == "asc" ? "ASC" : "DESC"

        column =
          case key
          when "revision_request_updated_at" then "claims.v_revision_request_grid.revision_request_updated_at"
          when "revision_request_created_at" then "claims.v_revision_request_grid.revision_request_created_at"
          when "session_created_at" then "claims.v_revision_request_grid.session_created_at"
          when "invoice_version_updated_at" then "claims.v_revision_request_grid.invoice_version_updated_at"
          when "revision_request_status" then "claims.v_revision_request_grid.revision_request_status"
          when "invoice_versionno" then "claims.v_revision_request_grid.invoice_versionno"
          else
            "claims.v_revision_request_grid.revision_request_updated_at"
          end

        Arel.sql("#{column} #{dir} NULLS LAST")
      end
    end
  end
end
