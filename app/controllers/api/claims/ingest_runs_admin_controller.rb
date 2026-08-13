# frozen_string_literal: true

module Api
  module Claims
    class IngestRunsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_after_action :verify_authorized, only: %i[index show steps show_step]
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
        diagnostics_by_run_id = attempt_diagnostics_by_run_id(rows)

        render json: {
                 rows:
                   rows.map do |row|
                     serialize_run(
                       row,
                       diagnostics: diagnostics_by_run_id[row.id.to_s]
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

      # GET /api/claims/admin/ingest_runs/:ingest_run_id
      def show
        row = ::Claims::VIngestRun.find(params[:ingest_run_id])
        diagnostics = attempt_diagnostics_by_run_id([row])[row.id.to_s]

        render json: serialize_run(row, diagnostics: diagnostics), status: :ok
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
        diagnostics = attempt_diagnostics_for_run(run)
        labels = target_labels(rows)

        render json: {
                 rows:
                   rows.map do |row|
                     serialize_step(
                       row,
                       attempt: diagnostics.annotations_by_step_id[row.id.to_s],
                       labels: labels
                     )
                   end,
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
        run = ::Claims::VIngestRun.find(row.ingest_run_id)
        diagnostics = attempt_diagnostics_for_run(run)
        render json:
                 serialize_step(
                   row,
                   include_payloads: true,
                   attempt: diagnostics.annotations_by_step_id[row.id.to_s],
                   labels: target_labels([row])
                 ),
               status: :ok
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
          OR EXISTS (
            SELECT 1
            FROM claims.ingest_step_runs search_step
            WHERE search_step.ingest_run_id = v_ingest_runs.id
              AND (
                search_step.id::text ILIKE :like
                OR search_step.diagnostic_id ILIKE :like
                OR search_step.error_code ILIKE :like
                OR search_step.provider_code ILIKE :like
              )
          )
          OR EXISTS (
            SELECT 1
            FROM claims.ingest_documents search_document
            WHERE search_document.ingest_run_id = v_ingest_runs.id
              AND (
                search_document.id::text ILIKE :like
                OR search_document.original_filename ILIKE :like
              )
          )
        SQL
      end

      def normalized_status(value)
        status = value.to_s.strip
        return if status.blank?

        allowed =
          ::Claims::IngestRun::ACTIVE_STATUSES +
            ::Claims::IngestRun::TERMINAL_STATUSES
        status if allowed.include?(status)
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

      def serialize_run(row, diagnostics: nil)
        {
          id: row.id,
          run_kind: row.run_kind,
          session_id: row.session_id,
          invoice_id: row.invoice_id,
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
          failure_category: row.failure_category,
          failure_code: row.failure_code,
          attempt_summary: diagnostics&.summary,
          terminal_failure:
            serialize_terminal_failure(diagnostics&.terminal_failure_step),
          created_at: row.created_at,
          updated_at: row.updated_at,
          completed_at: row.completed_at,
          duration_seconds: row.duration_seconds
        }
      end

      def serialize_step(row, include_payloads: false, attempt: nil, labels: {})
        upgrade_type =
          labels.fetch(:upgrade_types, {})[row.invoice_upgrade_type_id]
        supporting_type =
          labels.fetch(:supporting_types, {})[row.supporting_document_type_id]
        payload = {
          id: row.id,
          ingest_run_id: row.ingest_run_id,
          session_id: row.session_id,
          invoice_version_id: row.invoice_version_id,
          ingest_document_id: row.ingest_document_id,
          ingest_document_original_filename:
            row.ingest_document_original_filename,
          invoice_upgrade_type_id: row.invoice_upgrade_type_id,
          invoice_upgrade_type_key: upgrade_type&.upgrade_type_key,
          invoice_upgrade_type_description: upgrade_type&.description,
          supporting_document_type_id: row.supporting_document_type_id,
          supporting_document_type_key: supporting_type&.type_key,
          supporting_document_type_description: supporting_type&.description,
          step_type: row.step_type,
          status: row.status,
          **(attempt || {}),
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

      def attempt_diagnostics_by_run_id(runs)
        runs_by_id = Array(runs).index_by { |run| run.id.to_s }
        steps_by_run_id =
          ::Claims::IngestStepRun
            .where(ingest_run_id: runs_by_id.keys)
            .order(:created_at, :id)
            .group_by { |step| step.ingest_run_id.to_s }

        runs_by_id.transform_values do |run|
          ::Claims::Ingest::AttemptDiagnostics.call(
            steps: steps_by_run_id.fetch(run.id.to_s, []),
            run_status: run.status
          )
        end
      end

      def attempt_diagnostics_for_run(run)
        attempt_diagnostics_by_run_id([run]).fetch(run.id.to_s)
      end

      def target_labels(rows)
        upgrade_type_ids = rows.filter_map(&:invoice_upgrade_type_id).uniq
        supporting_type_ids =
          rows.filter_map(&:supporting_document_type_id).uniq
        {
          upgrade_types:
            ::Claims::InvoiceUpgradeType.where(id: upgrade_type_ids).index_by(
              &:id
            ),
          supporting_types:
            ::Claims::SupportingDocumentType.where(
              id: supporting_type_ids
            ).index_by(&:id)
        }
      end

      def serialize_terminal_failure(step)
        return if step.nil?

        {
          step_id: step.id,
          step_type: step.step_type,
          error_text: step.error_text,
          **serialize_step_diagnostics(step)
        }
      end

      def serialize_step_diagnostics(row)
        {
          failure_category: row.failure_category,
          failure_code: row.failure_code,
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
