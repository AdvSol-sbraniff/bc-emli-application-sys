# frozen_string_literal: true

module Api
  module Claims
    class ValidationRulesAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      RECORD_TYPES = %w[
        code_rule
        code_located_field
        genai_rule
        genai_located_field
      ].freeze
      CREATEABLE_RECORD_TYPES = %w[genai_rule genai_located_field].freeze

      skip_after_action :verify_authorized,
                        only: %i[index create update history upgrade_types]
      skip_after_action :verify_policy_scoped, only: %i[index upgrade_types]
      skip_forgery_protection only: %i[create update]

      def upgrade_types
        code_rule_counts =
          ::Claims::CodeRuleUpgradeType.group(:invoice_upgrade_type_id).count
        genai_rule_counts =
          ::Claims::GenaiRuleUpgradeType.group(:invoice_upgrade_type_id).count
        genai_field_counts =
          ::Claims::GenaiLocatedFieldUpgradeType.group(
            :invoice_upgrade_type_id
          ).count
        code_field_count = ::Claims::CodeLocatedField.count

        rows =
          ::Claims::InvoiceUpgradeType
            .order(
              Arel.sql(
                "CASE WHEN claims.invoice_upgrade_types.upgrade_type_key = 'common' THEN 0 ELSE 1 END"
              ),
              :upgrade_type_key
            )
            .map do |row|
              {
                id: row.id,
                upgrade_type_key: row.upgrade_type_key,
                description: row.description,
                code_rules_count: code_rule_counts[row.id] || 0,
                code_fields_count: code_field_count,
                genai_rules_count: genai_rule_counts[row.id] || 0,
                genai_fields_count: genai_field_counts[row.id] || 0
              }
            end

        render json: { rows: rows }, status: :ok
      end

      def index
        invoice_upgrade_type_id =
          params[:invoice_upgrade_type_id].to_s.strip.presence
        q = params[:q].to_s.strip
        type_filter = params[:record_type].to_s.strip.presence

        rows = []
        rows.concat serialized_code_rules(
                      invoice_upgrade_type_id,
                      q,
                      type_filter
                    )
        rows.concat serialized_code_located_fields(q, type_filter)
        rows.concat serialized_genai_rules(
                      invoice_upgrade_type_id,
                      q,
                      type_filter
                    )
        rows.concat serialized_genai_located_fields(
                      invoice_upgrade_type_id,
                      q,
                      type_filter
                    )

        render json: {
                 rows:
                   rows.sort_by do |row|
                     [type_rank(row[:record_type]), row[:record_key].to_s]
                   end
               },
               status: :ok
      end

      def create
        type = record_type_param
        unless CREATEABLE_RECORD_TYPES.include?(type)
          render json: {
                   error: "Creation is not allowed for #{type}."
                 },
                 status: :unprocessable_entity
          return
        end

        row =
          case type
          when "genai_rule"
            create_genai_rule!
          when "genai_located_field"
            create_genai_located_field!
          end

        render json: serialize_row(row, type), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def update
        type = record_type_param

        row =
          case type
          when "code_rule"
            update_code_rule!
          when "code_located_field"
            update_code_located_field!
          when "genai_rule"
            update_genai_rule!
          when "genai_located_field"
            update_genai_located_field!
          end

        render json: serialize_row(row, type), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def history
        type = record_type_param
        id = params[:id]

        render json: serialize_history(type, id), status: :ok
      end

      private

      def record_type_param
        type = params[:record_type].to_s.strip
        unless RECORD_TYPES.include?(type)
          raise ActionController::BadRequest, "Unsupported record_type"
        end

        type
      end

      def type_rank(record_type)
        case record_type
        when "code_rule"
          0
        when "genai_rule"
          1
        when "genai_located_field"
          2
        when "code_located_field"
          3
        else
          9
        end
      end

      def maybe_like(q)
        return nil if q.blank?

        "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      end

      def serialized_code_rules(invoice_upgrade_type_id, q, type_filter)
        return [] if type_filter.present? && type_filter != "code_rule"

        scope = ::Claims::CodeRule.includes(:invoice_upgrade_types)
        like = maybe_like(q)

        if invoice_upgrade_type_id.present?
          scope =
            scope.joins(:code_rule_upgrade_types).where(
              "claims.code_rule_upgrade_types.invoice_upgrade_type_id = ?",
              invoice_upgrade_type_id
            )
        end

        if like
          scope =
            scope.where(
              "claims.code_rules.code_rule_key ILIKE :like OR claims.code_rules.contractor_display_name ILIKE :like OR claims.code_rules.description ILIKE :like OR claims.code_rules.admin_notes ILIKE :like",
              like: like
            )
        end

        scope
          .order(:code_rule_key)
          .distinct
          .map { |row| serialize_row(row, "code_rule") }
      end

      def serialized_code_located_fields(q, type_filter)
        return [] if type_filter.present? && type_filter != "code_located_field"

        scope = ::Claims::CodeLocatedField.all
        like = maybe_like(q)

        if like
          scope =
            scope.where(
              "claims.code_located_fields.code_field_key ILIKE :like OR claims.code_located_fields.contractor_display_name ILIKE :like OR claims.code_located_fields.description ILIKE :like",
              like: like
            )
        end

        scope
          .order(:code_field_key)
          .map { |row| serialize_row(row, "code_located_field") }
      end

      def serialized_genai_rules(invoice_upgrade_type_id, q, type_filter)
        return [] if type_filter.present? && type_filter != "genai_rule"

        scope =
          ::Claims::GenaiRule.includes(
            :invoice_upgrade_types,
            :genai_rule_upgrade_types
          )
        like = maybe_like(q)

        if invoice_upgrade_type_id.present?
          scope =
            scope.joins(:genai_rule_upgrade_types).where(
              "claims.genai_rule_upgrade_types.invoice_upgrade_type_id = ?",
              invoice_upgrade_type_id
            )
        end

        if like
          scope =
            scope.where(
              "claims.genai_rules.genai_rule_key ILIKE :like OR claims.genai_rules.contractor_display_name ILIKE :like OR claims.genai_rules.prompt_text ILIKE :like",
              like: like
            )
        end

        scope
          .order(:genai_rule_key)
          .distinct
          .map { |row| serialize_row(row, "genai_rule") }
      end

      def serialized_genai_located_fields(
        invoice_upgrade_type_id,
        q,
        type_filter
      )
        if type_filter.present? && type_filter != "genai_located_field"
          return []
        end

        scope =
          ::Claims::GenaiLocatedField.includes(
            :invoice_upgrade_types,
            :genai_located_field_upgrade_types
          )
        like = maybe_like(q)

        if invoice_upgrade_type_id.present?
          scope =
            scope.joins(:genai_located_field_upgrade_types).where(
              "claims.genai_located_field_upgrade_types.invoice_upgrade_type_id = ?",
              invoice_upgrade_type_id
            )
        end

        if like
          scope =
            scope.where(
              "claims.genai_located_fields.genai_field_key ILIKE :like OR claims.genai_located_fields.contractor_display_name ILIKE :like OR claims.genai_located_fields.prompt_text ILIKE :like",
              like: like
            )
        end

        scope
          .order(:genai_field_key)
          .distinct
          .map { |row| serialize_row(row, "genai_located_field") }
      end

      def create_code_rule!
        ::Claims::CodeRule.transaction do
          row = ::Claims::CodeRule.create!(code_rule_params)
          sync_code_rule_mappings!(row)
          row.reload
        end
      end

      def update_code_rule!
        ::Claims::CodeRule.transaction do
          row = ::Claims::CodeRule.lock.find(params[:id])
          row.update!(code_rule_params)
          sync_code_rule_mappings!(row)
          row.reload
        end
      end

      def create_code_located_field!
        ::Claims::CodeLocatedField.transaction do
          ::Claims::CodeLocatedField.create!(code_located_field_params)
        end
      end

      def update_code_located_field!
        ::Claims::CodeLocatedField.transaction do
          row = ::Claims::CodeLocatedField.lock.find(params[:id])
          row.update!(code_located_field_params)
          row.reload
        end
      end

      def create_genai_rule!
        ::Claims::GenaiRule.transaction do
          row = ::Claims::GenaiRule.create!(genai_rule_params)
          sync_genai_rule_mappings!(row)
          row.reload
        end
      end

      def update_genai_rule!
        ::Claims::GenaiRule.transaction do
          row = ::Claims::GenaiRule.lock.find(params[:id])
          row.update!(genai_rule_params)
          sync_genai_rule_mappings!(row)
          row.reload
        end
      end

      def create_genai_located_field!
        ::Claims::GenaiLocatedField.transaction do
          row = ::Claims::GenaiLocatedField.create!(genai_located_field_params)
          sync_genai_located_field_mappings!(row)
          row.reload
        end
      end

      def update_genai_located_field!
        ::Claims::GenaiLocatedField.transaction do
          row = ::Claims::GenaiLocatedField.lock.find(params[:id])
          row.update!(genai_located_field_params)
          sync_genai_located_field_mappings!(row)
          row.reload
        end
      end

      def sync_code_rule_mappings!(row)
        mappings = normalized_mappings(params[:mappings], nil)
        ensure_mappings_present!(row, mappings)

        existing =
          row.code_rule_upgrade_types.index_by do |item|
            item.invoice_upgrade_type_id.to_s
          end
        keep_ids = mappings.map { |item| item[:invoice_upgrade_type_id] }

        existing.each_value do |mapping|
          next if keep_ids.include?(mapping.invoice_upgrade_type_id.to_s)

          mapping.destroy!
        end

        mappings.each do |item|
          next if existing[item[:invoice_upgrade_type_id]]

          row.code_rule_upgrade_types.create!(
            invoice_upgrade_type_id: item[:invoice_upgrade_type_id]
          )
        end
      end

      def sync_genai_rule_mappings!(row)
        mappings = normalized_mappings(params[:mappings], nil)
        ensure_mappings_present!(row, mappings)

        existing =
          row.genai_rule_upgrade_types.index_by do |item|
            item.invoice_upgrade_type_id.to_s
          end
        keep_ids = mappings.map { |item| item[:invoice_upgrade_type_id] }

        existing.each_value do |mapping|
          next if keep_ids.include?(mapping.invoice_upgrade_type_id.to_s)

          mapping.destroy!
        end

        mappings.each do |item|
          mapping = existing[item[:invoice_upgrade_type_id]]
          unless mapping
            row.genai_rule_upgrade_types.create!(
              invoice_upgrade_type_id: item[:invoice_upgrade_type_id]
            )
          end
        end
      end

      def sync_genai_located_field_mappings!(row)
        mappings = normalized_mappings(params[:mappings], nil)
        ensure_mappings_present!(row, mappings)

        existing =
          row.genai_located_field_upgrade_types.index_by do |item|
            item.invoice_upgrade_type_id.to_s
          end
        keep_ids = mappings.map { |item| item[:invoice_upgrade_type_id] }

        existing.each_value do |mapping|
          next if keep_ids.include?(mapping.invoice_upgrade_type_id.to_s)

          mapping.destroy!
        end

        next_field_number =
          existing
            .values
            .select do |mapping|
              keep_ids.include?(mapping.invoice_upgrade_type_id.to_s)
            end
            .map(&:field_number)
            .compact
            .max
            .to_i

        mappings.each do |item|
          mapping = existing[item[:invoice_upgrade_type_id]]
          unless mapping
            next_field_number += 1
            row.genai_located_field_upgrade_types.create!(
              invoice_upgrade_type_id: item[:invoice_upgrade_type_id],
              field_number: next_field_number
            )
          end
        end
      end

      def normalized_mappings(raw_value, order_key)
        Array
          .wrap(raw_value)
          .filter_map do |entry|
            hash =
              case entry
              when ActionController::Parameters
                entry.to_unsafe_h
              when Hash
                entry
              else
                nil
              end

            next if hash.blank?

            invoice_upgrade_type_id = hash["invoice_upgrade_type_id"].to_s.strip
            next if invoice_upgrade_type_id.blank?

            row = { invoice_upgrade_type_id: invoice_upgrade_type_id }
            row[order_key] = [hash[order_key.to_s].to_i, 1].max if order_key
            row
          end
      end

      def ensure_mappings_present!(row, mappings)
        return if mappings.present?

        row.errors.add(:base, "At least one upgrade type mapping is required.")
        raise ActiveRecord::RecordInvalid, row
      end

      def code_rule_params
        params.permit(
          :code_rule_key,
          :contractor_display_name,
          :description,
          :enabled,
          :pass_admin_message,
          :warn_admin_message,
          :fail_admin_message,
          :info_admin_message,
          :admin_notes,
          :source_quote,
          :contractor_visibility,
          :contractor_blocking_policy
        )
      end

      def code_located_field_params
        params.permit(
          :code_field_key,
          :contractor_display_name,
          :description,
          :enabled
        )
      end

      def genai_rule_params
        params.permit(
          :genai_rule_key,
          :contractor_display_name,
          :prompt_text,
          :enabled,
          :source_quote,
          :contractor_visibility,
          :contractor_blocking_policy
        )
      end

      def genai_located_field_params
        params.permit(
          :genai_field_key,
          :contractor_display_name,
          :prompt_text,
          :enabled
        )
      end

      def serialize_upgrade_types(upgrade_types)
        upgrade_types
          .sort_by(&:upgrade_type_key)
          .map do |item|
            {
              id: item.id,
              upgrade_type_key: item.upgrade_type_key,
              description: item.description
            }
          end
      end

      def serialize_row(row, record_type)
        case record_type
        when "code_rule"
          {
            id: row.id,
            record_type: record_type,
            record_key: row.code_rule_key,
            enabled: row.enabled,
            updated_at: row.updated_at,
            created_at: row.created_at,
            upgrade_types: serialize_upgrade_types(row.invoice_upgrade_types),
            detail: {
              contractor_display_name: row.contractor_display_name,
              description: row.description,
              pass_admin_message: row.pass_admin_message,
              warn_admin_message: row.warn_admin_message,
              fail_admin_message: row.fail_admin_message,
              info_admin_message: row.info_admin_message,
              admin_notes: row.admin_notes,
              source_quote: row.source_quote,
              contractor_visibility: row.contractor_visibility,
              contractor_blocking_policy: row.contractor_blocking_policy
            },
            mappings:
              row.code_rule_upgrade_types.map do |mapping|
                {
                  id: mapping.id,
                  invoice_upgrade_type_id: mapping.invoice_upgrade_type_id
                }
              end
          }
        when "code_located_field"
          {
            id: row.id,
            record_type: record_type,
            record_key: row.code_field_key,
            enabled: row.enabled,
            updated_at: row.updated_at,
            created_at: row.created_at,
            upgrade_types: [],
            detail: {
              contractor_display_name: row.contractor_display_name,
              description: row.description,
              global_scope: true
            },
            mappings: []
          }
        when "genai_rule"
          {
            id: row.id,
            record_type: record_type,
            record_key: row.genai_rule_key,
            enabled: row.enabled,
            updated_at: row.updated_at,
            created_at: row.created_at,
            upgrade_types: serialize_upgrade_types(row.invoice_upgrade_types),
            detail: {
              contractor_display_name: row.contractor_display_name,
              prompt_text: row.prompt_text,
              source_quote: row.source_quote,
              contractor_visibility: row.contractor_visibility,
              contractor_blocking_policy: row.contractor_blocking_policy
            },
            mappings:
              row.genai_rule_upgrade_types.map do |mapping|
                {
                  id: mapping.id,
                  invoice_upgrade_type_id: mapping.invoice_upgrade_type_id
                }
              end
          }
        when "genai_located_field"
          {
            id: row.id,
            record_type: record_type,
            record_key: row.genai_field_key,
            enabled: row.enabled,
            updated_at: row.updated_at,
            created_at: row.created_at,
            upgrade_types: serialize_upgrade_types(row.invoice_upgrade_types),
            detail: {
              contractor_display_name: row.contractor_display_name,
              prompt_text: row.prompt_text
            },
            mappings:
              row.genai_located_field_upgrade_types.map do |mapping|
                {
                  id: mapping.id,
                  invoice_upgrade_type_id: mapping.invoice_upgrade_type_id,
                  field_number: mapping.field_number
                }
              end
          }
        end
      end

      def serialize_history(record_type, id)
        case record_type
        when "code_rule"
          {
            row_history:
              ::Claims::CodeRuleHistory
                .where(source_id: id)
                .order(history_created_at: :desc)
                .map(&:attributes),
            mapping_history:
              ::Claims::CodeRuleUpgradeTypeHistory
                .where(code_rule_id: id)
                .order(history_created_at: :desc)
                .map(&:attributes)
          }
        when "code_located_field"
          {
            row_history:
              ::Claims::CodeLocatedFieldHistory
                .where(source_id: id)
                .order(history_created_at: :desc)
                .map(&:attributes),
            mapping_history: []
          }
        when "genai_rule"
          {
            row_history:
              ::Claims::GenaiRuleHistory
                .where(source_id: id)
                .order(history_created_at: :desc)
                .map(&:attributes),
            mapping_history:
              ::Claims::GenaiRuleUpgradeTypeHistory
                .where(genai_rule_id: id)
                .order(history_created_at: :desc)
                .map(&:attributes)
          }
        when "genai_located_field"
          {
            row_history:
              ::Claims::GenaiLocatedFieldHistory
                .where(source_id: id)
                .order(history_created_at: :desc)
                .map(&:attributes),
            mapping_history:
              ::Claims::GenaiLocatedFieldUpgradeTypeHistory
                .where(genai_field_id: id)
                .order(history_created_at: :desc)
                .map(&:attributes)
          }
        end
      end
    end
  end
end
