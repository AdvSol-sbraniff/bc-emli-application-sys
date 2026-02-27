# frozen_string_literal: true

module Api
  module Claims
    class InvoiceGridController < Api::ApplicationController
      # POC: no auth/policy for now (match your SessionsController approach)
skip_before_action :authenticate_user!, only: %i[index]
skip_before_action :require_confirmation, only: %i[index]
skip_after_action  :verify_authorized, only: %i[index]
skip_after_action  :verify_policy_scoped, only: %i[index]
skip_forgery_protection only: %i[index]

      # GET /api/claims/admin/invoices
      # Query:
      # - session_id=uuid (optional)
      # - invoice_status=string (optional)
      # - q=string (optional, ILIKE across whitelisted columns)
      # - sort=field:dir  (dir = asc|desc)
      # - page=int (default 1)
      # - per=int  (default 25, max 200)
      def index
        rel = ::Claims::InvoiceGrid.all

        # Filters
        if params[:session_id].present?
          rel = rel.where(session_id: params[:session_id].to_s.strip)
        end

        if params[:invoice_status].present?
          rel = rel.where(invoice_status: params[:invoice_status].to_s.strip)
        end

        # Text search (safe against missing columns)
        rel = apply_text_search(rel, params[:q])

        # Sort (safe against missing columns)
        sort_field, sort_dir = parse_sort(params[:sort])
        rel = rel.order(Arel.sql("#{sort_field} #{sort_dir}"))

        # Pagination
        page = to_int(params[:page], 1)
        per  = clamp(to_int(params[:per], 25), 1, 200)
        offset = (page - 1) * per

        total = rel.count
        rows  = rel.offset(offset).limit(per)

        render json: {
          rows: rows.as_json,
          meta: {
            total: total,
            page: page,
            per: per,
            sort: "#{sort_field}:#{sort_dir}",
            filters: {
              session_id: params[:session_id].presence,
              invoice_status: params[:invoice_status].presence,
              q: params[:q].presence
            }
          }
        }, status: :ok
      rescue => e
        Rails.logger.error("[CLAIMS][INVOICE_GRID] ERROR: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :internal_server_error
      end

      private

      def to_int(v, default)
        Integer(v)
      rescue
        default
      end

      def clamp(n, lo, hi)
        [[n, lo].max, hi].min
      end

      def sanitize_like(str)
        # escape % and _ for LIKE patterns
        str.to_s.gsub("\\", "\\\\\\").gsub("%", "\\%").gsub("_", "\\_")
      end

      def apply_text_search(rel, q)
        q = q.to_s.strip
        return rel if q.blank?

        cols = ::Claims::InvoiceGrid.column_names

        # keep this small + useful
        candidates = %w[
          contractor_business_name
          contractor_number
          contractor_email
          submitter_email
          submitter_name
          latest_di_ocr_invoice_id
          latest_di_ocr_vendor_name
          latest_original_filename
        ]

        fields = candidates.select { |c| cols.include?(c) }
        return rel if fields.empty?

        pattern = "%#{sanitize_like(q)}%"

        clauses = fields.map { |f| "#{f} ILIKE :p ESCAPE '\\\\'" }.join(" OR ")
        rel.where(clauses, p: pattern)
      end

      def parse_sort(raw)
        cols = ::Claims::InvoiceGrid.column_names

        default_field = cols.include?("latest_invoice_version_updated_at") ? "latest_invoice_version_updated_at" : "invoice_updated_at"
        default_dir   = "desc"

        return [default_field, default_dir] if raw.blank?

        field, dir = raw.to_s.split(":", 2)
        field = field.to_s.strip
        dir   = dir.to_s.strip.downcase

        field = default_field unless cols.include?(field)
        dir   = %w[asc desc].include?(dir) ? dir : default_dir

        [field, dir]
      end
    end
  end
end