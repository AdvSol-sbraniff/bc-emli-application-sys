# app/controllers/api/invoice_versions_controller.rb
module Api
  class InvoiceVersionsController < Api::ApplicationController
    # For the POC: don’t require login + don’t require policy checks
    skip_before_action :authenticate_user!, only: %i[show]
    skip_before_action :require_confirmation, only: %i[show]
    skip_after_action :verify_authorized, only: %i[show]

    def show
      invoice_version = Claims::InvoiceVersion.find_by(id: params[:id])

      if invoice_version.nil?
        render json: { error: "InvoiceVersion not found", id: params[:id] }, status: :not_found
        return
      end

      render json: {
        id: invoice_version.id,
        created_at: invoice_version.created_at,
        updated_at: invoice_version.updated_at,
        invoice_id: invoice_version.try(:invoice_id),
        status: "ok"
      }
    end
  end
end

