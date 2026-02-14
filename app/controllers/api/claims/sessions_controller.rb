# app/controllers/api/claims/sessions_controller.rb
module Api
  module Claims
    class SessionsController < Api::ApplicationController
      # For the POC: don’t require login + don’t require policy checks
      skip_before_action :verify_authenticity_token, only: %i[create]
      skip_before_action :authenticate_user!, only: %i[create]
      skip_before_action :require_confirmation, only: %i[create]
      skip_after_action :verify_authorized, only: %i[create]
      

      # POST /api/claims/sessions
      # Body: { contractor_id: "..." }
      def create
        contractor_id = params[:contractor_id].presence
        if contractor_id.blank?
          render json: { error: "contractor_id is required" }, status: :bad_request
          return
        end

        result = ::Claims::Sessions::Create.call(contractor_id: contractor_id)

        render json: {
          session_id: result.session.id,
          status: result.session.status
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      rescue => e
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
