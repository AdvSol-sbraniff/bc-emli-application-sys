# frozen_string_literal: true

module Api
  module Claims
    class NeeaProductsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.configuration"

      skip_after_action :verify_authorized,
                        only: %i[index import_status import_downloaded_pdf]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[import_downloaded_pdf]

      # GET /api/claims/admin/neea_products
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
            OR configuration ILIKE :like
            OR specification_version ILIKE :like
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

      # GET /api/claims/admin/neea_products/import_status
      def import_status
        source_rows =
          neea_sources.map do |source|
            latest =
              ::Claims::NeeaImportRun
                .where(neea_source_id: source.id)
                .order(started_at: :desc)
                .first

            latest_success =
              ::Claims::NeeaImportRun
                .where(neea_source_id: source.id, status: "succeeded")
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
          ::Claims::NeeaImportRun
            .where(neea_source_id: neea_source_ids)
            .order(started_at: :desc)
            .first

        latest_success =
          ::Claims::NeeaImportRun
            .where(neea_source_id: neea_source_ids, status: "succeeded")
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

      # POST /api/claims/admin/neea_products/import_downloaded_pdf
      def import_downloaded_pdf
        result =
          ::Claims::ExternalReferences::ImportNeeaHpwhProducts.call(
            neea_source_id: permitted_neea_source_id,
            publishing_date: params[:publishing_date],
            publishing_notes: params[:publishing_notes]
          )

        status = result[:ok] ? :ok : :unprocessable_entity
        render json: result, status: status
      end

      private

      def current_products
        scope = ::Claims::CurrentNeeaProduct.all
        if params[:neea_source_id].present?
          scope = scope.where(neea_source_id: permitted_neea_source_id)
        end
        scope
      end

      def neea_sources
        ::Claims::NeeaSource.order(:description, :id)
      end

      def neea_source_ids
        neea_sources.map(&:id)
      end

      def permitted_neea_source_id
        id = params[:neea_source_id].to_s.strip.presence

        return id if neea_source_ids.map(&:to_s).include?(id)

        raise ActionController::BadRequest, "Unknown neea_source_id #{id}"
      end

      def serialize_import_run(run)
        {
          id: run.id,
          neea_source_id: run.neea_source_id,
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
          model_number_regex: row.model_number_regex,
          model_components: row.model_components,
          storage_volume_gallons: row.storage_volume_gallons,
          indoor_tier: row.indoor_tier,
          indoor_cce: row.indoor_cce,
          outdoor_tier: row.outdoor_tier,
          outdoor_scop: row.outdoor_scop,
          configuration: row.configuration,
          flex_load_connectivity: row.flex_load_connectivity,
          plug_in_endorsement: row.plug_in_endorsement,
          qualified_date: row.qualified_date,
          specification_version: row.specification_version,
          eligibility_notes: row.eligibility_notes,
          neea_source_id: row.read_attribute("neea_source_id"),
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
          when "storage_volume_gallons"
            "storage_volume_gallons"
          when "indoor_tier"
            "indoor_tier"
          when "outdoor_tier"
            "outdoor_tier"
          when "qualified_date"
            "qualified_date"
          else
            "brand"
          end

        Arel.sql("#{column} #{dir} NULLS LAST")
      end
    end
  end
end
