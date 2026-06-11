# frozen_string_literal: true

module Api
  module Claims
    class InternalNotesAdminController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!, only: %i[index create]
      skip_before_action :require_confirmation, only: %i[index create]
      skip_after_action :verify_authorized, only: %i[index create]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index create]

      # GET /api/claims/admin/internal_notes?invoice_id=...
      def index
        invoice_id = params[:invoice_id].to_s.strip
        if invoice_id.blank?
          return(
            render json: {
                     error: "invoice_id is required"
                   },
                   status: :bad_request
          )
        end

        ::Claims::Invoice.find(invoice_id)

        rows =
          ::Claims::InternalNote
            .includes(:admin_user)
            .where(invoice_id: invoice_id)
            .order(created_at: :desc, id: :desc)

        render json: {
                 rows: rows.map { |row| serialize_record(row) }
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound => e
        render json: { error: e.message }, status: :not_found
      end

      # POST /api/claims/admin/internal_notes
      def create
        record = ::Claims::InternalNote.create!(create_params)

        render json: serialize_record(record), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ActiveRecord::InvalidForeignKey,
             ActiveRecord::StatementInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def create_params
        params.permit(:invoice_id, :admin_user_id, :note_text)
      end

      def serialize_record(record)
        admin_user = record.admin_user
        admin_user_name =
          admin_user.name.to_s.strip.presence ||
            admin_user.email.to_s.presence || record.admin_user_id

        {
          id: record.id,
          invoice_id: record.invoice_id,
          admin_user_id: record.admin_user_id,
          admin_user_name: admin_user_name,
          note_text: record.note_text,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      end
    end
  end
end
