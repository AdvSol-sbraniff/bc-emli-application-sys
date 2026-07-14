# frozen_string_literal: true

module Api
  module Claims
    class SupportingDocumentTypeLocatedFieldsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_after_action :verify_authorized, only: %i[index show create update]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[create update]

      def index
        supporting_document_type =
          ::Claims::SupportingDocumentType.find(
            params[:supporting_document_type_id]
          )

        rows =
          supporting_document_type
            .supporting_document_type_located_fields
            .order(:field_number, :field_key)
            .map { |row| serialize_row(row) }

        render json: {
                 supporting_document_type:
                   serialize_type(supporting_document_type),
                 rows: rows
               },
               status: :ok
      end

      def show
        row = ::Claims::SupportingDocumentTypeLocatedField.find(params[:id])

        render json: serialize_row(row, include_type: true), status: :ok
      end

      def create
        supporting_document_type =
          ::Claims::SupportingDocumentType.find(
            params[:supporting_document_type_id]
          )
        row =
          supporting_document_type.supporting_document_type_located_fields.create!(
            create_params
          )

        render json: serialize_row(row, include_type: true), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def update
        row = ::Claims::SupportingDocumentTypeLocatedField.find(params[:id])
        row.update!(update_params)

        render json: serialize_row(row, include_type: true), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def create_params
        params.permit(
          :field_key,
          :contractor_display_name,
          :prompt_text,
          :field_number,
          :enabled
        )
      end

      def update_params
        params.permit(
          :field_key,
          :contractor_display_name,
          :prompt_text,
          :field_number,
          :enabled
        )
      end

      def serialize_row(row, include_type: false)
        payload = {
          id: row.id,
          supporting_document_type_id: row.supporting_document_type_id,
          field_key: row.field_key,
          contractor_display_name: row.contractor_display_name,
          prompt_text: row.prompt_text,
          field_number: row.field_number,
          enabled: row.enabled,
          created_at: row.created_at,
          updated_at: row.updated_at
        }

        if include_type
          payload[:supporting_document_type] = serialize_type(
            row.supporting_document_type
          )
        end

        payload
      end

      def serialize_type(row)
        return nil if row.nil?

        {
          id: row.id,
          type_key: row.type_key,
          description: row.description,
          enabled: row.enabled
        }
      end
    end
  end
end
