# frozen_string_literal: true

module Api
  module Claims
    class IngestRunsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_after_action :verify_authorized, only: %i[index steps show_step]
      skip_after_action :verify_policy_scoped, only: %i[index]

      # GET /api/claims/admin/ingest_runs
      def index
        page = clamp_int(params[:page], 1, 1, 10_000)
        per = clamp_int(params[:per], 25, 1, 100)
        q = params[:q].to_s.strip
        status = normalized_status(params[:status])
        sort_column, sort_direction = normalized_sort(params[:sort])

        scope = ::Claims::VIngestRun.all
        scope = scope.where(status: status) if status.present?
        scope = apply_search(scope, q)
        total = scope.count
        rows =
          scope
            .order(Arel.sql("#{sort_column} #{sort_direction}"))
            .offset((page - 1) * per)
            .limit(per)
            .to_a
        failures_by_run_id = primary_failures_by_run_id(rows.map(&:id))

        render json: {
                 rows:
                   rows.map do |row|
                     serialize_run(
                       row,
                       primary_failure: failures_by_run_id[row.id.to_s]
                     )
                   end,
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort:
                     "#{sort_column.split(".").last}:#{sort_direction.downcase}",
                   filters: {
                     q: q.presence,
                     status: status
                   }
                 }
               },
               status: :ok
      end

      # GET /api/claims/admin/ingest_runs/:ingest_run_id/steps
      def steps
        run = ::Claims::VIngestRun.find(params[:ingest_run_id])
        page = clamp_int(params[:page], 1, 1, 10_000)
        per = clamp_int(params[:per], 100, 1, 500)
        sort_direction =
          params[:sort].to_s.downcase == "created_at:desc" ? "DESC" : "ASC"

        scope =
          ::Claims::VIngestStepRun.where(ingest_run_id: run.id).order(
            Arel.sql("created_at #{sort_direction}, id #{sort_direction}")
          )
        total = scope.count
        rows = scope.offset((page - 1) * per).limit(per)

        render json: {
                 rows: rows.map { |row| serialize_step(row) },
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: "created_at:#{sort_direction.downcase}",
                   ingest_run_id: run.id
                 }
               },
               status: :ok
      end

      # GET /api/claims/admin/ingest_step_runs/:id
      def show_step
        row = ::Claims::VIngestStepRun.find(params[:id])
        render json: serialize_step(row, include_payloads: true), status: :ok
      end

      private

      def apply_search(scope, q)
        return scope if q.blank?

        like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
        scope.where(<<~SQL.squish, like: like)
          v_ingest_runs.id::text ILIKE :like
          OR v_ingest_runs.session_id::text ILIKE :like
          OR v_ingest_runs.contractor_id::text ILIKE :like
          OR v_ingest_runs.resolved_invoice_version_id::text ILIKE :like
          OR v_ingest_runs.contractor_business_name ILIKE :like
          OR v_ingest_runs.contractor_number ILIKE :like
          OR v_ingest_runs.pipeline_error_code ILIKE :like
        SQL
      end

      def normalized_status(value)
        status = value.to_s.strip
        return if status.blank?

        status if %w[queued running succeeded failed partial].include?(status)
      end

      def normalized_sort(value)
        key, direction = value.to_s.split(":", 2)
        column =
          case key
          when "updated_at"
            "v_ingest_runs.updated_at"
          when "completed_at"
            "v_ingest_runs.completed_at"
          when "contractor_business_name"
            "v_ingest_runs.contractor_business_name"
          when "status"
            "v_ingest_runs.status"
          else
            "v_ingest_runs.created_at"
          end
        direction = direction.to_s.downcase == "asc" ? "ASC" : "DESC"
        [column, direction]
      end

      def clamp_int(value, default, minimum, maximum)
        number = Integer(value)
        [[number, minimum].max, maximum].min
      rescue ArgumentError, TypeError
        default
      end

      def serialize_run(row, primary_failure: nil)
        {
          id: row.id,
          session_id: row.session_id,
          contractor_id: row.contractor_id,
          contractor_business_name: row.contractor_business_name,
          contractor_number: row.contractor_number,
          resolved_invoice_version_id: row.resolved_invoice_version_id,
          status: row.status,
          cleanup_failed_invoice_artifacts:
            row.cleanup_failed_invoice_artifacts,
          total_files: row.total_files,
          completed_files: row.completed_files,
          failed_files: row.failed_files,
          pipeline_error_code: row.pipeline_error_code,
          pipeline_error_description: row.pipeline_error_description,
          failure_status: row.failure_status,
          failure_status_subtype: row.failure_status_subtype,
          primary_failure:
            primary_failure && serialize_step_diagnostics(primary_failure),
          created_at: row.created_at,
          updated_at: row.updated_at,
          completed_at: row.completed_at,
          duration_seconds: row.duration_seconds
        }
      end

      def serialize_step(row, include_payloads: false)
        payload = {
          id: row.id,
          ingest_run_id: row.ingest_run_id,
          session_id: row.session_id,
          invoice_version_id: row.invoice_version_id,
          ingest_document_id: row.ingest_document_id,
          ingest_document_original_filename:
            row.ingest_document_original_filename,
          invoice_upgrade_type_id: row.invoice_upgrade_type_id,
          supporting_document_type_id: row.supporting_document_type_id,
          step_type: row.step_type,
          status: row.status,
          error_text: row.error_text,
          **serialize_step_diagnostics(row),
          has_di_results_json: row.di_results_json.present?,
          has_genai_results_json: row.genai_results_json.present?,
          has_context_window_json: row.context_window_json.present?,
          created_at: row.created_at,
          updated_at: row.updated_at,
          completed_at: row.completed_at,
          duration_seconds: row.duration_seconds
        }
        if include_payloads
          payload.merge!(
            di_results_json: row.di_results_json,
            genai_results_json: row.genai_results_json,
            context_window_json: row.context_window_json
          )
        end
        payload
      end

      def primary_failures_by_run_id(run_ids)
        rows =
          ::Claims::IngestStepRun
            .where(ingest_run_id: run_ids, status: "failed")
            .order(created_at: :asc, id: :asc)
            .group_by { |row| row.ingest_run_id.to_s }

        rows.transform_values do |steps|
          ::Claims::Invoices::FailureSubtypes.primary_failed_step(steps)
        end
      end

      def serialize_step_diagnostics(row)
        {
          failure_status: row.failure_status,
          failure_status_subtype: row.failure_status_subtype,
          error_code: row.error_code,
          error_category: row.error_category,
          error_phase: row.error_phase,
          retryable: row.retryable,
          diagnostic_id: row.diagnostic_id,
          provider_status: row.provider_status,
          provider_code: row.provider_code,
          provider_attempt_count: row.provider_attempt_count
        }
      end
    end
  end
end
