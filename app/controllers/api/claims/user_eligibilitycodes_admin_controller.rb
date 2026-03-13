# frozen_string_literal: true

module Api
  module Claims
    class UserEligibilitycodesAdminController < ApplicationController
      skip_before_action :authenticate_user!, only: %i[index show create update]
      skip_before_action :require_confirmation, only: %i[index show create update]
      skip_after_action :verify_authorized, only: %i[index show create update]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index show create update]

      # GET /api/claims/admin/user_eligibilitycodes?q=&sort=&page=&per=
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "users_eligibilitycode_updated_at:desc"

        scope = ::Claims::VUserEligibilitycode.all

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(
            <<~SQL.squish,
              CAST(claims.v_user_eligibilitycodes.user_id AS text) ILIKE :like
              OR claims.v_user_eligibilitycodes.email ILIKE :like
              OR claims.v_user_eligibilitycodes.first_name ILIKE :like
              OR claims.v_user_eligibilitycodes.last_name ILIKE :like
              OR claims.v_user_eligibilitycodes.role ILIKE :like
              OR claims.v_user_eligibilitycodes.omniauth_provider ILIKE :like
              OR claims.v_user_eligibilitycodes.eligibility_code ILIKE :like
              OR CAST(claims.v_user_eligibilitycodes.users_eligibilitycode_id AS text) ILIKE :like
            SQL
            like: like
          )
        end

        scope = scope.order(order_clause(sort))
        total = scope.count

        rows = scope
          .offset((page - 1) * per)
          .limit(per)
          .map { |r| serialize_row(r) }

        render json: {
          rows: rows,
          meta: {
            total: total,
            page: page,
            per: per,
            sort: sort,
            filters: { q: q.presence }
          }
        }
      end

      # GET /api/claims/admin/users_eligibilitycodes/:id
      def show
        record = ::Claims::UsersEligibilitycode.find(params[:id])

        render json: {
          id: record.id,
          user_id: record.user_id,
          eligibility_code: record.eligibility_code,
          applied_at: record.applied_at,
          approved_at: record.approved_at,
          expires_at: record.expires_at,
          created_at: record.created_at,
          updated_at: record.updated_at
        }, status: :ok
      end

      # POST /api/claims/admin/users_eligibilitycodes
      # Body: { user_id, eligibility_code, applied_at, approved_at, expires_at }
      def create
        record = ::Claims::UsersEligibilitycode.new(create_params)
        record.save!

        render json: {
          id: record.id,
          user_id: record.user_id,
          eligibility_code: record.eligibility_code,
          applied_at: record.applied_at,
          approved_at: record.approved_at,
          expires_at: record.expires_at,
          created_at: record.created_at,
          updated_at: record.updated_at
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      # PATCH /api/claims/admin/users_eligibilitycodes/:id
      # Body: { eligibility_code, applied_at, approved_at, expires_at }
      def update
        record = ::Claims::UsersEligibilitycode.find(params[:id])
        record.update!(update_params)

        render json: {
          id: record.id,
          user_id: record.user_id,
          eligibility_code: record.eligibility_code,
          applied_at: record.applied_at,
          approved_at: record.approved_at,
          expires_at: record.expires_at,
          created_at: record.created_at,
          updated_at: record.updated_at
        }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      private

      def create_params
        params.permit(:user_id, :eligibility_code, :applied_at, :approved_at, :expires_at)
      end

      def update_params
        params.permit(:eligibility_code, :applied_at, :approved_at, :expires_at)
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
          when "email" then "claims.v_user_eligibilitycodes.email"
          when "role" then "claims.v_user_eligibilitycodes.role"
          when "first_name" then "claims.v_user_eligibilitycodes.first_name"
          when "last_name" then "claims.v_user_eligibilitycodes.last_name"
          when "user_created_at" then "claims.v_user_eligibilitycodes.user_created_at"
          when "eligibility_code" then "claims.v_user_eligibilitycodes.eligibility_code"
          when "applied_at" then "claims.v_user_eligibilitycodes.applied_at"
          when "approved_at" then "claims.v_user_eligibilitycodes.approved_at"
          when "expires_at" then "claims.v_user_eligibilitycodes.expires_at"
          when "users_eligibilitycode_created_at" then "claims.v_user_eligibilitycodes.users_eligibilitycode_created_at"
          when "users_eligibilitycode_updated_at" then "claims.v_user_eligibilitycodes.users_eligibilitycode_updated_at"
          else
            "claims.v_user_eligibilitycodes.users_eligibilitycode_updated_at"
          end

        Arel.sql("#{column} #{dir}")
      end

      def serialize_row(r)
        {
          user_id: r.user_id,
          email: r.email,
          organization: r.organization,
          certified: r.certified,
          user_created_at: r.user_created_at,
          user_updated_at: r.user_updated_at,
          role: r.role,
          first_name: r.first_name,
          last_name: r.last_name,
          omniauth_provider: r.omniauth_provider,
          omniauth_uid: r.omniauth_uid,
          discarded_at: r.discarded_at,
          sign_in_count: r.sign_in_count,
          current_sign_in_at: r.current_sign_in_at,
          last_sign_in_at: r.last_sign_in_at,
          unconfirmed_email: r.unconfirmed_email,
          omniauth_email: r.omniauth_email,
          omniauth_username: r.omniauth_username,
          reviewed: r.reviewed,
          users_eligibilitycode_id: r.users_eligibilitycode_id,
          eligibilitycode_user_id: r.eligibilitycode_user_id,
          eligibility_code: r.eligibility_code,
          applied_at: r.applied_at,
          approved_at: r.approved_at,
          expires_at: r.expires_at,
          users_eligibilitycode_created_at: r.users_eligibilitycode_created_at,
          users_eligibilitycode_updated_at: r.users_eligibilitycode_updated_at
        }
      end
    end
  end
end
