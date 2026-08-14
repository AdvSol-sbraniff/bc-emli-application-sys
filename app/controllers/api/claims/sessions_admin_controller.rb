# frozen_string_literal: true

module Api
  module Claims
    class SessionsAdminController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.test_tools"

      skip_before_action :authenticate_user!, only: %i[show update]
      skip_before_action :require_confirmation, only: %i[show update]
      skip_after_action :verify_authorized, only: %i[show update]
      skip_forgery_protection only: %i[show update]

      # GET /api/claims/admin/sessions/:id
      def show
        render json: serialize_session(find_session), status: :ok
      end

      # PATCH /api/claims/admin/sessions/:id
      # Body: { submitter_id: "...", submitted_at: "YYYY-MM-DD" }
      def update
        session = find_session

        result =
          ::Claims::Sessions::Update.call(
            session: session,
            submitter_id: params[:submitter_id],
            submitted_at: params[:submitted_at]
          )

        render json: serialize_session(result.session.reload), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ArgumentError => e
        render json: { error: e.message }, status: :bad_request
      end

      private

      def find_session
        ::Claims::Session.find(params[:id])
      end

      def serialize_session(session)
        representative_invoice =
          ::Claims::Invoice
            .where(session_id: session.id)
            .order(:created_at, :id)
            .first
        contractor =
          ::Contractor.find_by(id: representative_invoice&.contractor_id)
        submitter = ::User.find_by(id: representative_invoice&.submitter_id)

        {
          id: session.id,
          contractor_id: representative_invoice&.contractor_id,
          submitter_id: representative_invoice&.submitter_id,
          created_at: session.created_at,
          updated_at: session.updated_at,
          submitted_at: representative_invoice&.submitted_at,
          contractor: {
            id: contractor&.id,
            business_name: contractor&.business_name,
            contractor_number: contractor&.number,
            email: contractor&.email,
            phone_number: contractor&.phone_number,
            city: contractor&.city
          },
          submitter: {
            id: submitter&.id,
            email: submitter&.email,
            first_name: submitter&.first_name,
            last_name: submitter&.last_name,
            role: submitter&.role,
            organization: submitter&.organization,
            omniauth_provider: submitter&.omniauth_provider
          }
        }
      end
    end
  end
end
