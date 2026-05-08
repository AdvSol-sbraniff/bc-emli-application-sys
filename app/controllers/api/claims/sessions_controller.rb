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
      # Body: { contractor_id: "...", submitter_id: "...", submitted_at: "YYYY-MM-DD" }
      def create
        contractor_id = params[:contractor_id].presence
        submitter_id = params[:submitter_id].presence
        submitted_at = params[:submitted_at].presence
        if contractor_id.blank?
          render json: {
                   error: "contractor_id is required"
                 },
                 status: :bad_request
          return
        end

        if submitter_id.present? ^ submitted_at.present?
          render json: {
                   error:
                     "submitter_id and submitted_at must either both be provided or both be blank"
                 },
                 status: :bad_request
          return
        end

        result =
          ::Claims::Sessions::Create.call(
            contractor_id: contractor_id,
            submitter_id: submitter_id,
            submitted_at: submitted_at
          )

        render json: {
                 session_id: result.session.id,
                 submitted_at: submitted_at
               },
               status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue => e
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
