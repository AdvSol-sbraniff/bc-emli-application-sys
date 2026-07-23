# frozen_string_literal: true

module Api
  module Claims
    class CodeRulesAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_after_action :verify_authorized, only: %i[index update]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[update]

      # GET /api/claims/admin/code_rules
      def index
        q = params[:q].to_s.strip
        enabled = params[:enabled].to_s.strip.presence
        invoice_upgrade_type_id =
          params[:invoice_upgrade_type_id].to_s.strip.presence

        scope = ::Claims::CodeRule.includes(:invoice_upgrade_types)

        if enabled.present?
          scope =
            scope.where(enabled: ActiveModel::Type::Boolean.new.cast(enabled))
        end

        if invoice_upgrade_type_id.present?
          scope =
            scope.joins(:code_rule_upgrade_types).where(
              "claims.code_rule_upgrade_types.invoice_upgrade_type_id = ?",
              invoice_upgrade_type_id
            )
        end

        if q.present?
          like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
          scope =
            scope.where(
              "claims.code_rules.code_rule_key ILIKE :like OR claims.code_rules.contractor_display_name ILIKE :like OR claims.code_rules.description ILIKE :like OR claims.code_rules.admin_notes ILIKE :like",
              like: like
            )
        end

        rows =
          scope
            .order(:code_rule_key)
            .distinct
            .map { |rule| serialize_rule(rule) }

        render json: { rows: rows }, status: :ok
      end

      # PATCH /api/claims/admin/code_rules/:id
      def update
        rule = ::Claims::CodeRule.find(params[:id])
        rule.update!(update_params)

        render json: serialize_rule(rule.reload), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      private

      def update_params
        params.permit(
          :contractor_display_name,
          :description,
          :enabled,
          :pass_admin_message,
          :warn_admin_message,
          :fail_admin_message,
          :info_admin_message,
          :admin_notes,
          :source_quote,
          :contractor_action,
          :contractor_visibility,
          :contractor_blocking_policy
        )
      end

      def serialize_rule(rule)
        {
          id: rule.id,
          code_rule_key: rule.code_rule_key,
          contractor_display_name: rule.contractor_display_name,
          description: rule.description,
          enabled: rule.enabled,
          pass_admin_message: rule.pass_admin_message,
          warn_admin_message: rule.warn_admin_message,
          fail_admin_message: rule.fail_admin_message,
          info_admin_message: rule.info_admin_message,
          admin_notes: rule.admin_notes,
          source_quote: rule.source_quote,
          contractor_action: rule.contractor_action,
          contractor_visibility: rule.contractor_visibility,
          contractor_blocking_policy: rule.contractor_blocking_policy,
          created_at: rule.created_at,
          updated_at: rule.updated_at,
          upgrade_types:
            rule
              .invoice_upgrade_types
              .sort_by(&:upgrade_type_key)
              .map do |ut|
                {
                  id: ut.id,
                  upgrade_type_key: ut.upgrade_type_key,
                  description: ut.description
                }
              end
        }
      end
    end
  end
end
