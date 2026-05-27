# frozen_string_literal: true

module Api
  module Claims
    class SupportingDocumentTypesAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_after_action :verify_authorized, only: %i[index show create update]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[create update]

      def index
        q = params[:q].to_s.strip
        scope = ::Claims::SupportingDocumentType.all
        like = maybe_like(q)

        if like
          scope =
            scope.where(
              "claims.supporting_document_types.type_key ILIKE :like OR claims.supporting_document_types.description ILIKE :like",
              like: like
            )
        end

        counts =
          ::Claims::SupportingDocument
            .group(:supporting_document_type_id)
            .count

        rows =
          scope.order(:type_key).map do |row|
            serialize_row(
              row,
              supporting_documents_count: counts[row.id] || 0
            )
          end

        render json: { rows: rows }, status: :ok
      end

      def show
        row = ::Claims::SupportingDocumentType.find(params[:id])
        count =
          ::Claims::SupportingDocument.where(
            supporting_document_type_id: row.id
          ).count

        render json: serialize_row(row, supporting_documents_count: count),
               status: :ok
      end

      def create
        row = ::Claims::SupportingDocumentType.new(create_params)
        row.save!

        render json: serialize_row(row, supporting_documents_count: 0),
               status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def update
        row = ::Claims::SupportingDocumentType.find(params[:id])
        row.update!(update_params)

        count =
          ::Claims::SupportingDocument.where(
            supporting_document_type_id: row.id
          ).count

        render json: serialize_row(row, supporting_documents_count: count),
               status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def create_params
        params.permit(:type_key, :description, :enabled)
      end

      def update_params
        params.permit(:type_key, :description, :enabled)
      end

      def serialize_row(row, supporting_documents_count:)
        {
          id: row.id,
          type_key: row.type_key,
          description: row.description,
          enabled: row.enabled,
          created_at: row.created_at,
          updated_at: row.updated_at,
          supporting_documents_count: supporting_documents_count
        }
      end

      def maybe_like(q)
        return nil if q.blank?

        "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      end
    end
  end
end
