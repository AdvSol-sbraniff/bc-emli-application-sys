# frozen_string_literal: true

module Api
  module Claims
    class UsersAdminController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.test_tools"

      skip_before_action :authenticate_user!,
                         only: %i[index show create update destroy]
      skip_before_action :require_confirmation,
                         only: %i[index show create update destroy]
      skip_after_action :verify_authorized,
                        only: %i[index show create update destroy]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index show create update destroy]

      ROLE_OPTIONS = ::User.roles.keys.freeze

      # GET /api/claims/admin/users?q=&sort=&page=&per=
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "updated_at:desc"

        scope = ::User.kept

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
              CAST(users.id AS text) ILIKE :like
              OR users.email ILIKE :like
              OR users.first_name ILIKE :like
              OR users.last_name ILIKE :like
              OR users.organization ILIKE :like
              OR #{role_name_sql} ILIKE :like
              OR users.omniauth_provider ILIKE :like
              OR users.omniauth_uid ILIKE :like
              OR users.omniauth_email ILIKE :like
              OR users.omniauth_username ILIKE :like
            SQL
        end

        scope = scope.order(order_clause(sort))
        total = scope.count

        rows =
          scope
            .offset((page - 1) * per)
            .limit(per)
            .map { |user| serialize_user(user) }

        render json: {
                 rows: rows,
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: sort,
                   role_options: ROLE_OPTIONS,
                   filters: {
                     q: q.presence
                   }
                 }
               },
               status: :ok
      end

      # GET /api/claims/admin/users/:id
      def show
        render json: serialize_user(find_user), status: :ok
      end

      # POST /api/claims/admin/users
      def create
        user =
          ::User.new(
            create_params.merge(
              discarded_at: nil,
              password: Devise.friendly_token[0, 20]
            )
          )

        user.save!

        render json: serialize_user(user), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      # PATCH /api/claims/admin/users/:id
      def update
        user = find_user

        with_claims_role_editor { user.update!(update_params) }

        render json: serialize_user(user), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      # DELETE /api/claims/admin/users/:id
      def destroy
        user = find_user

        if current_user.present? && current_user.id == user.id
          render json: {
                   error: "You cannot delete your own user."
                 },
                 status: :forbidden
          return
        end

        if user.discard
          render json: { ok: true, id: user.id }, status: :ok
        else
          render json: {
                   error: "Failed to delete user."
                 },
                 status: :unprocessable_entity
        end
      end

      private

      def find_user
        ::User.kept.find(params[:id])
      end

      def create_params
        permitted =
          params.permit(
            :email,
            :organization,
            :role,
            :first_name,
            :last_name,
            :reviewed,
            :certified,
            :omniauth_provider,
            :omniauth_uid,
            :omniauth_email,
            :omniauth_username
          )

        normalize_user_params(permitted)
      end

      def update_params
        permitted =
          params.permit(
            :email,
            :organization,
            :role,
            :first_name,
            :last_name,
            :reviewed,
            :certified,
            :omniauth_provider,
            :omniauth_uid,
            :omniauth_email,
            :omniauth_username
          )

        normalize_user_params(permitted)
      end

      def normalize_user_params(permitted)
        attrs = permitted.to_h

        attrs.transform_values! do |value|
          value.is_a?(String) && value.strip.blank? ? nil : value
        end

        attrs["role"] = attrs["role"].to_s.strip if attrs.key?("role") &&
          attrs["role"].present?

        attrs
      end

      def serialize_user(user)
        {
          id: user.id,
          email: user.email,
          organization: user.organization,
          role: user.role,
          first_name: user.first_name,
          last_name: user.last_name,
          name: user.name,
          reviewed: user.reviewed,
          certified: user.certified,
          confirmed_at: user.confirmed_at,
          created_at: user.created_at,
          updated_at: user.updated_at,
          omniauth_provider: user.omniauth_provider,
          omniauth_uid: user.omniauth_uid,
          omniauth_email: user.omniauth_email,
          omniauth_username: user.omniauth_username,
          discarded_at: user.discarded_at,
          sign_in_count: user.sign_in_count,
          current_sign_in_at: user.current_sign_in_at,
          last_sign_in_at: user.last_sign_in_at,
          invitation_sent_at: user.invitation_sent_at,
          invitation_accepted_at: user.invitation_accepted_at,
          unconfirmed_email: user.unconfirmed_email
        }
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

      def sanitize_sql_like(string)
        string.to_s.gsub(/[\\%_]/) { |x| "\\#{x}" }
      end

      def order_clause(sort)
        key, dir = sort.to_s.split(":", 2)
        dir = dir&.downcase == "asc" ? "ASC" : "DESC"

        column =
          case key
          when "email"
            "users.email"
          when "first_name"
            "users.first_name"
          when "last_name"
            "users.last_name"
          when "organization"
            "users.organization"
          when "role"
            "users.role"
          when "created_at"
            "users.created_at"
          when "updated_at"
            "users.updated_at"
          when "last_sign_in_at"
            "users.last_sign_in_at"
          else
            "users.updated_at"
          end

        Arel.sql("#{column} #{dir}")
      end

      def role_name_sql
        @role_name_sql ||=
          begin
            cases =
              ::User
                .roles
                .map { |name, value| "WHEN #{value} THEN '#{name}'" }
                .join(" ")

            "CASE users.role #{cases} ELSE '' END"
          end
      end

      def with_claims_role_editor
        previous_user = Current.user
        Current.user ||= current_user || ::User.new(role: :system_admin)
        yield
      ensure
        Current.user = previous_user
      end
    end
  end
end
