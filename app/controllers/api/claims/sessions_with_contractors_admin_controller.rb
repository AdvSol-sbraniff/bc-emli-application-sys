# frozen_string_literal: true
# /app/controllers/api/claims/sessions_with_contractors_admin_controller.rb
module Api
  module Claims
    class SessionsWithContractorsAdminController < ApplicationController
      # TEMP: allow local dev to hit this without auth until KC is wired
      skip_before_action :authenticate_user!, only: %i[index]
      skip_before_action :require_confirmation, only: %i[index]
      skip_after_action  :verify_authorized, only: %i[index]
      skip_after_action  :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index]

      # GET /api/claims/admin/sessions_with_contractors?q=&status=&sort=&page=&per=
      def index
        per    = clamp_int(params[:per], 25, 1, 200)
        page   = clamp_int(params[:page], 1, 1, 10_000)
        q      = params[:q].to_s.strip
        status = params[:status].to_s.strip # optional: OPENBUTNOTSUBMITTED / OPENANDSUBMITTED / CLOSED
        sort   = params[:sort].to_s.strip.presence || "updated_at:desc"

        # View lives in claims schema
        scope = ::Claims::VSessionWithContractor.all

        if status.present?
          scope = scope.where(status: status)
        end

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(
            <<~SQL.squish,
              CAST(claims.v_sessions_with_contractors.id AS text) ILIKE :like
              OR CAST(claims.v_sessions_with_contractors.contractor_id AS text) ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_business_name ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_number ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_email ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_phone_number ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_cellphone_number ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_city ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_postal_code ILIKE :like
            SQL
            like: like
          )
        end

        scope = scope.order(order_clause(sort))
        total = scope.count

        sessions = scope
          .offset((page - 1) * per)
          .limit(per)

        rows = sessions.map do |s|
          {
            # session fields (from s.* in the view)
            id: s.id,
            contractor_id: s.contractor_id,
            submitter_id: s.submitter_id,
            status: s.status,
            created_at: s.created_at,
            updated_at: s.updated_at,
            submitted_at: s.submitted_at,

            # denormalized contractor fields (aliased in the view)
            contractor_business_name: s.contractor_business_name,
            contractor_number: s.contractor_number,
            contractor_email: s.contractor_email,
            contractor_phone_number: s.contractor_phone_number,
            contractor_cellphone_number: s.contractor_cellphone_number,
            contractor_city: s.contractor_city,
            contractor_postal_code: s.contractor_postal_code,
            contractor_onboarded: s.contractor_onboarded
          }
        end

        render json: {
          rows: rows,
          meta: {
            total: total,
            page: page,
            per: per,
            sort: sort,
            filters: {
              q: q.presence,
              status: status.presence
            }
          }
        }
      end

      private

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
          when "created_at"               then "claims.v_sessions_with_contractors.created_at"
          when "updated_at"               then "claims.v_sessions_with_contractors.updated_at"
          when "submitted_at"             then "claims.v_sessions_with_contractors.submitted_at"
          when "status"                   then "claims.v_sessions_with_contractors.status"
          when "contractor_business_name" then "claims.v_sessions_with_contractors.contractor_business_name"
          when "contractor_number"        then "claims.v_sessions_with_contractors.contractor_number"
          when "contractor_city"          then "claims.v_sessions_with_contractors.contractor_city"
          when "contractor_onboarded"     then "claims.v_sessions_with_contractors.contractor_onboarded"
          else
            "claims.v_sessions_with_contractors.updated_at"
          end

        Arel.sql("#{column} #{dir}")
      end
    end
  end
end