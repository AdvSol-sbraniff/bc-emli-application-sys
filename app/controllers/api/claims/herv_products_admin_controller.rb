# frozen_string_literal: true

module Api
  module Claims
    class HervProductsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.configuration"

      skip_after_action :verify_authorized,
                        only: %i[index import_status import_downloaded_csv]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[import_downloaded_csv]

      # GET /api/claims/admin/herv_products
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "brand:asc"

        scope = current_products

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
            brand ILIKE :like
            OR brand_normalized ILIKE :like
            OR model_number ILIKE :like
            OR model_number_normalized ILIKE :like
            OR model_type ILIKE :like
          SQL
        end

        scope = scope.order(order_clause(sort))
        total = scope.count
        rows = scope.offset((page - 1) * per).limit(per)

        render json: {
                 rows: rows.map { |row| serialize_product(row) },
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: sort,
                   filters: {
                     q: q.presence
                   }
                 }
               },
               status: :ok
      end

      # GET /api/claims/admin/herv_products/import_status
      def import_status
        source_rows =
          herv_sources.map do |source|
            latest =
              ::Claims::HervImportRun
                .where(herv_source_id: source.id)
                .order(started_at: :desc)
                .first

            latest_success =
              ::Claims::HervImportRun
                .where(herv_source_id: source.id, status: "succeeded")
                .order(started_at: :desc)
                .first

            {
              id: source.id,
              description: source.description,
              source_url: source.source_url,
              latest: latest ? serialize_import_run(latest) : nil,
              latest_success:
                latest_success ? serialize_import_run(latest_success) : nil
            }
          end

        latest =
          ::Claims::HervImportRun
            .where(herv_source_id: herv_source_ids)
            .order(started_at: :desc)
            .first

        latest_success =
          ::Claims::HervImportRun
            .where(herv_source_id: herv_source_ids, status: "succeeded")
            .order(started_at: :desc)
            .first

        render json: {
                 sources: source_rows,
                 latest: latest ? serialize_import_run(latest) : nil,
                 latest_success:
                   latest_success ? serialize_import_run(latest_success) : nil
               },
               status: :ok
      end

      # POST /api/claims/admin/herv_products/import_downloaded_csv
      def import_downloaded_csv
        result =
          ::Claims::ExternalReferences::ImportHervProducts.call(
            herv_source_id: permitted_herv_source_id,
            publishing_date: params[:publishing_date],
            publishing_notes: params[:publishing_notes]
          )

        status = result[:ok] ? :ok : :unprocessable_entity
        render json: result, status: status
      end

      private

      def current_products
        scope = ::Claims::CurrentHervProduct.all
        if params[:herv_source_id].present?
          scope = scope.where(herv_source_id: permitted_herv_source_id)
        end
        scope
      end

      def herv_sources
        ::Claims::HervSource.order(:description, :id)
      end

      def herv_source_ids
        herv_sources.map(&:id)
      end

      def permitted_herv_source_id
        id = params[:herv_source_id].to_s.strip.presence
        return id if herv_source_ids.map(&:to_s).include?(id)

        raise ActionController::BadRequest, "Unknown herv_source_id #{id}"
      end

      def serialize_import_run(run)
        {
          id: run.id,
          herv_source_id: run.herv_source_id,
          storage_provider: run.storage_provider,
          storage_key: run.storage_key,
          content_type: run.content_type,
          byte_size: run.byte_size,
          status: run.status,
          started_at: run.started_at,
          completed_at: run.completed_at,
          records_imported: run.records_imported,
          publishing_notes: run.publishing_notes,
          publishing_date: run.publishing_date,
          file_sha256: run.file_sha256,
          error_text: run.error_text,
          metadata_json: run.metadata_json
        }
      end

      def serialize_product(row)
        {
          id: row.id,
          brand: row.brand,
          brand_normalized: row.brand_normalized,
          model_number: row.model_number,
          model_number_normalized: row.model_number_normalized,
          model_type: row.model_type,
          sensible_heat_recovery_efficiency_sre_at_0c:
            row.sensible_heat_recovery_efficiency_sre_at_0c,
          sensible_heat_recovery_efficiency_sre_at_minus_25c:
            row.sensible_heat_recovery_efficiency_sre_at_minus_25c,
          associated_net_supply_airflow_at_0c_cfm:
            row.associated_net_supply_airflow_at_0c_cfm,
          associated_net_supply_airflow_at_minus_25c_cfm:
            row.associated_net_supply_airflow_at_minus_25c_cfm,
          associated_power_consumption_at_0c_w:
            row.associated_power_consumption_at_0c_w,
          associated_power_consumption_at_minus_25c_w:
            row.associated_power_consumption_at_minus_25c_w,
          max_rated_airflow_at_0c_cfm: row.max_rated_airflow_at_0c_cfm,
          power_consumption_at_0c_w: row.power_consumption_at_0c_w,
          eligibility_notes: row.eligibility_notes,
          herv_source_id: row.read_attribute("herv_source_id"),
          source_url: row.read_attribute("source_url"),
          source_description: row.read_attribute("source_description"),
          publishing_notes: row.read_attribute("publishing_notes"),
          publishing_date: row.read_attribute("publishing_date"),
          source_import_completed_at:
            row.read_attribute("source_import_completed_at")
        }
      end

      def clamp_int(value, default, min, max)
        n =
          begin
            Integer(value)
          rescue StandardError
            default
          end
        n = default if n.nil?
        n = min if n < min
        n = max if n > max
        n
      end

      def sanitize_sql_like(string)
        string.to_s.gsub(/[\\%_]/) { |x| "\\#{x}" }
      end

      def order_clause(sort)
        key, dir = sort.to_s.split(":", 2)
        dir = dir&.downcase == "desc" ? "DESC" : "ASC"

        column =
          case key
          when "brand"
            "brand"
          when "model_number"
            "model_number"
          when "model_type"
            "model_type"
          else
            "brand"
          end

        Arel.sql("#{column} #{dir} NULLS LAST")
      end
    end
  end
end
