# frozen_string_literal: true
# /app/controllers/api/claims/contractors_admin_controller.rb
module Api
  module Claims
    class ContractorsAdminController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      # TEMP: allow local dev to hit this without auth until KC is wired
      skip_before_action :authenticate_user!, only: %i[index]
      skip_before_action :require_confirmation, only: %i[index]
      skip_after_action :verify_authorized, only: %i[index]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index]

      # GET /api/claims/admin/contractors?q=&sort=&page=&per=
      def index
        per = clamp_int(params[:per], 25, 1, 100)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "business_name:asc"

        scope = ::Contractor.all

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
              contractors.business_name ILIKE :like
              OR contractors.number ILIKE :like
              OR contractors.email ILIKE :like
              OR contractors.phone_number ILIKE :like
              OR contractors.cellphone_number ILIKE :like
              OR contractors.city ILIKE :like
              OR contractors.postal_code ILIKE :like
            SQL
        end

        scope = scope.order(order_clause(sort))
        total = scope.count

        contractors = scope.offset((page - 1) * per).limit(per)

        rows =
          contractors.map do |c|
            {
              id: c.id,
              business_name: c.business_name,
              contractor_number: c.number,
              email: c.email,
              phone_number: c.phone_number,
              cellphone_number: c.cellphone_number,
              city: c.city,
              postal_code: c.postal_code,
              created_at: c.created_at,
              updated_at: c.updated_at
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
                     q: q.presence
                   }
                 }
               }
      end

      private

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

      def sanitize_sql_like(string)
        string.to_s.gsub(/[\\%_]/) { |x| "\\#{x}" }
      end

      def order_clause(sort)
        key, dir = sort.to_s.split(":", 2)
        dir = dir&.downcase == "desc" ? "DESC" : "ASC"

        column =
          case key
          when "business_name"
            "contractors.business_name"
          when "number"
            "contractors.number"
          when "email"
            "contractors.email"
          when "created_at"
            "contractors.created_at"
          when "updated_at"
            "contractors.updated_at"
          else
            "contractors.business_name"
          end

        Arel.sql("#{column} #{dir}")
      end
    end
  end
end
