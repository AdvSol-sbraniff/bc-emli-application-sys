# app/controllers/api/claims/validationgenai_rulesets_controller.rb
module Api
  module Claims
    class ValidationgenaiRulesetsController < Api::ApplicationController
      # POC: mirror your SessionsController approach (no auth for now)
      skip_before_action :verify_authenticity_token, only: %i[show update]
      skip_before_action :authenticate_user!, only: %i[show update]
      skip_before_action :require_confirmation, only: %i[show update]
      skip_after_action :verify_authorized, only: %i[show update]

      # GET /api/claims/admin/validationgenai_rulesets/:id
      def show
        ruleset = ::Claims::ValidationgenaiRuleset.find(params[:id])

        render json: serialize_ruleset(ruleset), status: :ok
      end

      # PATCH /api/claims/admin/validationgenai_rulesets/:id
      # Body: { ruleset_shortname, system_record, user_record1 }
      def update
        ruleset = ::Claims::ValidationgenaiRuleset.find(params[:id])

        ruleset.update!(update_params)

        render json: serialize_ruleset(ruleset), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      private

      def update_params
        params.permit(:ruleset_shortname, :system_record, :user_record1)
      end

      def serialize_ruleset(r)
        {
          id: r.id,
          ruleset_shortname: r.ruleset_shortname,
          system_record: r.system_record,
          user_record1: r.user_record1,
          created_at: r.created_at,
          updated_at: r.updated_at
        }
      end
    end
  end
end