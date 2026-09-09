# frozen_string_literal: true

module Api
  module Claims
    class InvoiceVersionRulechecksAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :require_confirmation
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped
      skip_forgery_protection

      def update_reason_complaint
        rulecheck = ::Claims::InvoiceVersionRulecheck.find(params[:id])
        rulecheck.update!(reason_complaint_params)

        render json: serialize_reason_complaint(rulecheck), status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Rulecheck not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      private

      def reason_complaint_params
        params.permit(:reason_complaint_code, :reason_complaint_text)
      end

      def serialize_reason_complaint(rulecheck)
        {
          id: rulecheck.id,
          reason_complaint_code: rulecheck.reason_complaint_code,
          reason_complaint_text: rulecheck.reason_complaint_text,
          updated_at: rulecheck.updated_at
        }
      end
    end
  end
end
