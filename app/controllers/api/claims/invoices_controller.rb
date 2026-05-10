# app/controllers/api/claims/invoices_controller.rb
module Api
  module Claims
    class InvoicesController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      # POC: allow admin testing without auth friction (match your other controller style)
      skip_before_action :authenticate_user!, only: %i[index_by_session]
      skip_before_action :require_confirmation, only: %i[index_by_session]
      skip_after_action :verify_authorized, only: %i[index_by_session]
      skip_forgery_protection only: %i[index_by_session]

      # GET /api/claims/sessions/:session_id/invoices
      def index_by_session
        session_id = params[:session_id].to_s.strip
        raise "Missing session_id in route." if session_id.empty?

        rows =
          ::Claims::Invoice
            .where(session_id: session_id)
            .order(created_at: :asc)
            .map do |i|
              {
                id: i.id,
                session_id: i.session_id,
                status: i.status,
                status_updated_at: i.status_updated_at,
                system_help_notes: i.system_help_notes,
                created_at: i.created_at,
                updated_at: i.updated_at
              }
            end

        render json: { invoices: rows }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoices][index_by_session] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 invoices: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end
    end
  end
end
