# frozen_string_literal: true

module Api
  module Claims
    class VentFanProductsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.configuration"

      skip_after_action :verify_authorized,
                        only: %i[index import_status import_downloaded_csv]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[import_downloaded_csv]

      # GET /api/claims/admin/vent_fan_products
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
            OR product_model_name ILIKE :like
            OR model_number ILIKE :like
            OR model_number_normalized ILIKE :like
            OR fan_type ILIKE :like
            OR energy_star_unique_id ILIKE :like
            OR cb_model_identifier ILIKE :like
            OR markets ILIKE :like
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

      # GET /api/claims/admin/vent_fan_products/import_status
      def import_status
        source_rows =
          vent_fan_sources.map do |source|
            latest =
              ::Claims::VentFanImportRun
                .where(vent_fan_source_id: source.id)
                .order(started_at: :desc)
                .first

            latest_success =
              ::Claims::VentFanImportRun
                .where(vent_fan_source_id: source.id, status: "succeeded")
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
          ::Claims::VentFanImportRun
            .where(vent_fan_source_id: vent_fan_source_ids)
            .order(started_at: :desc)
            .first

        latest_success =
          ::Claims::VentFanImportRun
            .where(vent_fan_source_id: vent_fan_source_ids, status: "succeeded")
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

      # POST /api/claims/admin/vent_fan_products/import_downloaded_csv
      def import_downloaded_csv
        result =
          ::Claims::ExternalReferences::ImportVentFanProducts.call(
            vent_fan_source_id: permitted_vent_fan_source_id,
            publishing_date: params[:publishing_date],
            publishing_notes: params[:publishing_notes]
          )

        status = result[:ok] ? :ok : :unprocessable_entity
        render json: result, status: status
      end

      private

      def current_products
        scope = ::Claims::CurrentVentFanProduct.all
        if params[:vent_fan_source_id].present?
          scope = scope.where(vent_fan_source_id: permitted_vent_fan_source_id)
        end
        scope
      end

      def vent_fan_sources
        ::Claims::VentFanSource.order(:description, :id)
      end

      def vent_fan_source_ids
        vent_fan_sources.map(&:id)
      end

      def permitted_vent_fan_source_id
        id = params[:vent_fan_source_id].to_s.strip.presence
        return id if vent_fan_source_ids.map(&:to_s).include?(id)

        raise ActionController::BadRequest, "Unknown vent_fan_source_id #{id}"
      end

      def serialize_import_run(run)
        {
          id: run.id,
          vent_fan_source_id: run.vent_fan_source_id,
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
          energy_star_unique_id: row.energy_star_unique_id,
          energy_star_partner: row.energy_star_partner,
          brand: row.brand,
          brand_normalized: row.brand_normalized,
          product_model_name: row.product_model_name,
          model_number: row.model_number,
          model_number_normalized: row.model_number_normalized,
          additional_model_information: row.additional_model_information,
          fan_type: row.fan_type,
          number_of_speeds: row.number_of_speeds,
          duct_size: row.duct_size,
          sound_level_sones: row.sound_level_sones,
          bathroom_utility_airflow_at_0_25_in_wg:
            row.bathroom_utility_airflow_at_0_25_in_wg,
          airflow_1_cfm: row.airflow_1_cfm,
          airflow_2_cfm: row.airflow_2_cfm,
          airflow_3_cfm: row.airflow_3_cfm,
          efficacy_1_cfm_watt: row.efficacy_1_cfm_watt,
          efficacy_2_cfm_watt: row.efficacy_2_cfm_watt,
          efficacy_3_cfm_watt: row.efficacy_3_cfm_watt,
          markets: row.markets,
          cb_model_identifier: row.cb_model_identifier,
          meets_most_efficient_criteria: row.meets_most_efficient_criteria,
          vent_fan_source_id: row.read_attribute("vent_fan_source_id"),
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
          when "fan_type"
            "fan_type"
          when "markets"
            "markets"
          else
            "brand"
          end

        Arel.sql("#{column} #{dir} NULLS LAST")
      end
    end
  end
end
