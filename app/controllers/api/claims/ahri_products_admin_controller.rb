# frozen_string_literal: true

module Api
  module Claims
    class AhriProductsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.configuration"

      skip_after_action :verify_authorized,
                        only: %i[index import_status import_downloaded_pdf]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[import_downloaded_pdf]

      # GET /api/claims/admin/ahri_products
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "ahri_reference_number:asc"

        scope = current_products

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
            ahri_reference_number ILIKE :like
            OR heat_pump_type ILIKE :like
            OR make ILIKE :like
            OR outdoor_model ILIKE :like
            OR indoor_model_or_air_handler ILIKE :like
            OR furnace_model ILIKE :like
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

      # GET /api/claims/admin/ahri_products/import_status
      def import_status
        source_rows =
          heat_pump_sources.map do |source|
            latest =
              ::Claims::AhriImportRun
                .where(ahri_source_id: source.id)
                .order(started_at: :desc)
                .first

            latest_success =
              ::Claims::AhriImportRun
                .where(ahri_source_id: source.id, status: "succeeded")
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
          ::Claims::AhriImportRun
            .where(ahri_source_id: heat_pump_source_ids)
            .order(started_at: :desc)
            .first

        latest_success =
          ::Claims::AhriImportRun
            .where(ahri_source_id: heat_pump_source_ids, status: "succeeded")
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

      # POST /api/claims/admin/ahri_products/import_downloaded_pdf
      def import_downloaded_pdf
        result =
          ::Claims::ExternalReferences::ImportBcHydroHeatPumpProducts.call(
            ahri_source_id: permitted_ahri_source_id,
            publishing_date: params[:publishing_date],
            publishing_notes: params[:publishing_notes]
          )

        status = result[:ok] ? :ok : :unprocessable_entity
        render json: result, status: status
      end

      private

      def current_products
        scope = ::Claims::CurrentAhriProduct.all
        if params[:ahri_source_id].present?
          scope = scope.where(ahri_source_id: permitted_ahri_source_id)
        end
        scope
      end

      def heat_pump_sources
        ::Claims::AhriSource.order(:description, :id)
      end

      def heat_pump_source_ids
        heat_pump_sources.map(&:id)
      end

      def permitted_ahri_source_id
        id = params[:ahri_source_id].to_s.strip.presence

        return id if heat_pump_source_ids.map(&:to_s).include?(id)

        raise ActionController::BadRequest, "Unknown ahri_source_id #{id}"
      end

      def serialize_import_run(run)
        {
          id: run.id,
          ahri_source_id: run.ahri_source_id,
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
          ahri_reference_number: row.ahri_reference_number,
          heat_pump_type: row.heat_pump_type,
          make: row.make,
          outdoor_model: row.outdoor_model,
          indoor_model_or_air_handler: row.indoor_model_or_air_handler,
          furnace_model: row.furnace_model,
          rated_capacity_btu_at_minus_5c: row.rated_capacity_btu_at_minus_5c,
          seer: row.seer,
          seer2: row.seer2,
          hspf: row.hspf,
          hspf2: row.hspf2,
          cop: row.cop,
          capacity_maintenance_percent: row.capacity_maintenance_percent,
          cold_climate_rated: row.cold_climate_rated,
          eligibility_notes: row.eligibility_notes,
          ahri_source_id: row.read_attribute("ahri_source_id"),
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
          when "ahri_reference_number"
            "ahri_reference_number"
          when "make"
            "make"
          when "outdoor_model"
            "outdoor_model"
          when "seer2"
            "seer2"
          when "hspf2"
            "hspf2"
          else
            "ahri_reference_number"
          end

        Arel.sql("#{column} #{dir} NULLS LAST")
      end
    end
  end
end
