# frozen_string_literal: true

module Api
  module Claims
    class SupportingDocumentTypesAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.configuration"

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

        rows = scope.order(:type_key).map { |row| serialize_row(row) }

        render json: { rows: rows }, status: :ok
      end

      def show
        row = ::Claims::SupportingDocumentType.find(params[:id])
        render json: serialize_row(row), status: :ok
      end

      def create
        row = nil

        ::Claims::SupportingDocumentType.transaction do
          row = ::Claims::SupportingDocumentType.new(create_params)
          row.save!
          sync_upgrade_type_mappings!(row, params[:invoice_upgrade_type_ids])
        end

        render json: serialize_row(row), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def update
        row = ::Claims::SupportingDocumentType.find(params[:id])

        ::Claims::SupportingDocumentType.transaction do
          row.update!(update_params)
          sync_upgrade_type_mappings!(row, params[:invoice_upgrade_type_ids])
        end

        render json: serialize_row(row), status: :ok
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
        params.permit(:type_key, :description, :enabled)
      end

      def update_params
        params.permit(:type_key, :description, :enabled)
      end

      def serialize_row(row)
        upgrade_types = serialize_upgrade_types(row)

        {
          id: row.id,
          type_key: row.type_key,
          description: row.description,
          enabled: row.enabled,
          created_at: row.created_at,
          updated_at: row.updated_at,
          invoice_upgrade_type_ids: upgrade_types.map { |it| it[:id] },
          upgrade_types: upgrade_types
        }
      end

      def serialize_upgrade_types(row)
        row
          .invoice_upgrade_types
          .order(
            Arel.sql(
              "CASE WHEN claims.invoice_upgrade_types.upgrade_type_key = 'common' THEN 0 ELSE 1 END"
            ),
            :upgrade_type_key
          )
          .map do |upgrade_type|
            {
              id: upgrade_type.id,
              upgrade_type_key: upgrade_type.upgrade_type_key,
              description: upgrade_type.description
            }
          end
      end

      def sync_upgrade_type_mappings!(row, raw_upgrade_type_ids)
        target_ids =
          Array(raw_upgrade_type_ids)
            .map { |value| value.to_s.strip }
            .reject(&:blank?)
            .uniq

        existing_ids =
          ::Claims::InvoiceUpgradeType.where(id: target_ids).pluck(:id)
        missing_ids = target_ids - existing_ids
        if missing_ids.any?
          row.errors.add(
            :base,
            "Unknown upgrade type ids: #{missing_ids.join(", ")}"
          )
          raise ActiveRecord::RecordInvalid, row
        end

        current_ids =
          row
            .supporting_document_type_upgrade_types
            .pluck(:invoice_upgrade_type_id)
            .map(&:to_s)

        ids_to_remove = current_ids - target_ids
        ids_to_add = target_ids - current_ids

        if ids_to_remove.any?
          row
            .supporting_document_type_upgrade_types
            .where(invoice_upgrade_type_id: ids_to_remove)
            .delete_all
        end

        ids_to_add.each do |upgrade_type_id|
          row.supporting_document_type_upgrade_types.create!(
            invoice_upgrade_type_id: upgrade_type_id,
            created_at: Time.current
          )
        end
      end

      def maybe_like(q)
        return nil if q.blank?

        "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      end
    end
  end
end
