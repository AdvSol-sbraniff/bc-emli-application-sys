# frozen_string_literal: true

module Api
  module Claims
    class ReportsVolumeValueController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!, only: %i[summary trend detail]
      skip_before_action :require_confirmation, only: %i[summary trend detail]
      skip_after_action :verify_authorized, only: %i[summary trend detail]
      skip_after_action :verify_policy_scoped, only: %i[summary trend detail]
      skip_forgery_protection only: %i[summary trend detail]

      # GET /api/claims/admin/reports/volume_value/summary
      def summary
        rel = filtered_relation

        invoice_count = rel.count
        total_value = rel.sum(:invoice_total_cad) || 0
        avg_value =
          rel.where.not(invoice_total_cad: nil).average(:invoice_total_cad)
        active_contractors =
          rel.where.not(contractor_id: nil).distinct.count(:contractor_id)

        amount_rel = rel.where.not(invoice_total_cad: nil)
        median_value =
          if amount_rel.exists?
            amount_rel.pick(
              Arel.sql(
                "PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY invoice_total_cad)"
              )
            )
          end

        render json: {
                 invoice_count: invoice_count,
                 total_value_cad: total_value.to_f,
                 avg_value_cad: avg_value&.to_f,
                 median_value_cad: median_value&.to_f,
                 active_contractors: active_contractors
               },
               status: :ok
      end

      # GET /api/claims/admin/reports/volume_value/trend?grain=day|week|month
      def trend
        rel = filtered_relation

        grain = params[:grain].to_s.downcase
        grain = "week" unless %w[day week month].include?(grain)
        period_expr = "date_trunc('#{grain}', invoice_created_at)"

        rows =
          rel
            .group(Arel.sql(period_expr))
            .order(Arel.sql("#{period_expr} ASC"))
            .pluck(
              Arel.sql(period_expr),
              Arel.sql("COUNT(*)"),
              Arel.sql("COALESCE(SUM(invoice_total_cad), 0)")
            )
            .map do |period_start, invoice_count, total_value|
              {
                period_start: period_start,
                invoice_count: invoice_count,
                total_value_cad: total_value.to_f
              }
            end

        render json: { grain: grain, rows: rows }, status: :ok
      end

      # GET /api/claims/admin/reports/volume_value/detail
      def detail
        rel = filtered_relation

        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        sort_field, sort_dir = parse_sort(params[:sort])

        total = rel.count
        rows =
          rel
            .order(Arel.sql("#{sort_field} #{sort_dir}"))
            .offset((page - 1) * per)
            .limit(per)

        render json: {
                 rows: rows.as_json,
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: "#{sort_field}:#{sort_dir.downcase}",
                   filters: filter_meta
                 }
               },
               status: :ok
      end

      private

      def filtered_relation
        rel = ::Claims::VReportingInvoiceBusiness.all

        if params[:status].present?
          rel = rel.where(invoice_status: params[:status].to_s.strip)
        end

        if params[:date_from].present?
          rel =
            rel.where(
              "invoice_created_at >= ?",
              parse_date_start(params[:date_from])
            )
        end

        if params[:date_to].present?
          rel =
            rel.where(
              "invoice_created_at <= ?",
              parse_date_end(params[:date_to])
            )
        end

        if params[:min_value].present?
          rel = rel.where("invoice_total_cad >= ?", params[:min_value].to_f)
        end

        if params[:max_value].present?
          rel = rel.where("invoice_total_cad <= ?", params[:max_value].to_f)
        end

        q = params[:q].to_s.strip
        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          rel = rel.where(<<~SQL.squish, like: like)
              CAST(claims.v_reporting_invoice_business.invoice_id AS text) ILIKE :like
              OR CAST(claims.v_reporting_invoice_business.session_id AS text) ILIKE :like
              OR claims.v_reporting_invoice_business.contractor_business_name ILIKE :like
              OR claims.v_reporting_invoice_business.contractor_number ILIKE :like
              OR claims.v_reporting_invoice_business.ocr_invoice_number ILIKE :like
            SQL
        end

        rel
      end

      def filter_meta
        {
          q: params[:q].presence,
          status: params[:status].presence,
          date_from: params[:date_from].presence,
          date_to: params[:date_to].presence,
          min_value: params[:min_value].presence,
          max_value: params[:max_value].presence
        }
      end

      def parse_date_start(value)
        Date.parse(value.to_s).beginning_of_day
      rescue ArgumentError
        Date.new(1970, 1, 1).beginning_of_day
      end

      def parse_date_end(value)
        Date.parse(value.to_s).end_of_day
      rescue ArgumentError
        Time.current.end_of_day
      end

      def sanitize_sql_like(string)
        string.to_s.gsub(/[\\%_]/) { |x| "\\#{x}" }
      end

      def clamp_int(value, default, min, max)
        n =
          begin
            Integer(value)
          rescue StandardError
            default
          end
        n = default if n.nil?
        n = min if n < min
        n = max if n > max
        n
      end

      def parse_sort(raw)
        key, dir = raw.to_s.split(":", 2)
        dir = dir.to_s.downcase == "asc" ? "ASC" : "DESC"

        column =
          case key
          when "invoice_created_at"
            "invoice_created_at"
          when "invoice_status"
            "invoice_status"
          when "contractor_business_name"
            "contractor_business_name"
          when "invoice_total_cad"
            "invoice_total_cad"
          when "invoice_id"
            "invoice_id"
          else
            "invoice_created_at"
          end

        [column, dir]
      end
    end
  end
end
