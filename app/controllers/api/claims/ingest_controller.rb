# app/controllers/api/claims/ingest_controller.rb

# ============================================================
# SECTION 00 — FILE OVERVIEW
# PURPOSE: Claims ingest endpoints (POC)
# NOTES:
# - Currently exposes only: POST upload (multipart pdfs[])
# - Returns structured "run report" JSON for React admin screen
# - Logs via Rails.logger (docker compose logs -f app)
# ============================================================

# ============================================================
# SECTION 01 — CONTROLLER: Api::Claims::IngestController
# ============================================================

require "json"
require "net/http"
require "securerandom"

module Api
  module Claims
    class IngestController < Api::ApplicationController
      # POC: don’t require login + don’t require policy checks

      # ============================================================
      # SECTION 01.01 — AUTH / POLICY BYPASSES (POC ONLY)
      # PURPOSE: Allow testing without login/policy/CSRF friction.
      # ============================================================

      skip_before_action :authenticate_user!,
                         only: %i[
                           upload
                           upload_fix
                           runs_index
                           steps_index
                           steps_by_session_index
                           run_ocr
                           run_genai
                           run_show
                           run_invoices_index
                           steps_by_invoice_index
                           admin_submit_batch
                         ]
      skip_before_action :require_confirmation,
                         only: %i[
                           upload
                           upload_fix
                           runs_index
                           steps_index
                           steps_by_session_index
                           run_ocr
                           run_genai
                           run_show
                           run_invoices_index
                           steps_by_invoice_index
                           admin_submit_batch
                         ]
      skip_after_action :verify_authorized,
                        only: %i[
                          upload
                          upload_fix
                          runs_index
                          steps_index
                          steps_by_session_index
                          run_ocr
                          run_genai
                          run_show
                          run_invoices_index
                          steps_by_invoice_index
                          admin_submit_batch
                        ]
      skip_forgery_protection only: %i[
                                upload
                                upload_fix
                                runs_index
                                steps_index
                                steps_by_session_index
                                run_ocr
                                run_genai
                                run_show
                                run_invoices_index
                                steps_by_invoice_index
                                admin_submit_batch
                              ]

      # ============================================================
      # SECTION 01.50 — ACTION: runs_index
      # ROUTE: GET /api/claims/ingest/runs
      # PURPOSE:
      # - Returns recent claims.ingest_runs rows for the Run Tracker grid
      # - Optional filter: ?session_id=<uuid>
      # - Optional limit:  ?limit=25 (max 100)
      # ============================================================

      def runs_index
        session_id = params[:session_id].to_s.strip
        session_id = nil if session_id.empty?

        limit = params[:limit].to_i
        limit = 25 if limit <= 0
        limit = 100 if limit > 100

        scope = ::Claims::IngestRun.order(created_at: :desc)
        scope = scope.where(session_id: session_id) if session_id

        rows =
          scope
            .limit(limit)
            .map do |r|
              {
                id: r.id,
                session_id: r.session_id,
                status: r.status,
                total_files: r.total_files,
                completed_files: r.completed_files,
                failed_files: r.failed_files,
                created_at: r.created_at,
                updated_at: r.updated_at,
                completed_at: r.completed_at
              }
            end

        render json: { runs: rows }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][runs_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 runs: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 01.60 — ACTION: steps_index
      # ROUTE: GET /api/claims/ingest/runs/:ingest_run_id/steps
      # PURPOSE:
      # - Returns step rows (upload/di/genai) for a single ingest_run
      # ============================================================

      def steps_index
        ingest_run_id = params[:ingest_run_id].to_s.strip
        raise "Missing ingest_run_id in route." if ingest_run_id.empty?

        limit = params[:limit].to_i
        limit = 50 if limit <= 0
        limit = 200 if limit > 200

        scope =
          ::Claims::IngestStepRun.where(ingest_run_id: ingest_run_id).order(
            created_at: :desc
          )

        rows =
          scope
            .limit(limit)
            .map do |r|
              {
                id: r.id,
                ingest_run_id: r.ingest_run_id,
                invoice_version_id: r.invoice_version_id,
                step_type: r.step_type,
                status: r.status,
                error_text: r.error_text,
                validationgenai_ruleset_id:
                  (
                    if r.respond_to?(:validationgenai_ruleset_id)
                      r.validationgenai_ruleset_id
                    else
                      nil
                    end
                  ),
                created_at: r.created_at,
                updated_at: r.updated_at
              }
            end

        render json: { steps: rows }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][steps_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 steps: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 01.61 — ACTION: steps_by_session_index
      # ROUTE: GET /api/claims/ingest/steps?session_id=<uuid>
      # PURPOSE:
      # - Returns ingest_step_runs filtered by session_id
      # - Supports orphan/manual steps (ingest_run_id NULL) because session_id is on the table
      # ============================================================

      def steps_by_session_index
        session_id = params[:session_id].to_s.strip
        raise "Missing session_id in querystring." if session_id.empty?

        limit = params[:limit].to_i
        limit = 200 if limit <= 0
        limit = 500 if limit > 500

        scope =
          ::Claims::IngestStepRun.where(session_id: session_id).order(
            created_at: :desc
          )

        rows =
          scope
            .limit(limit)
            .map do |r|
              {
                id: r.id,
                ingest_run_id: r.ingest_run_id,
                session_id: r.session_id,
                invoice_version_id: r.invoice_version_id,
                step_type: r.step_type,
                status: r.status,
                error_text: r.error_text,
                validationgenai_ruleset_id:
                  (
                    if r.respond_to?(:validationgenai_ruleset_id)
                      r.validationgenai_ruleset_id
                    else
                      nil
                    end
                  ),
                created_at: r.created_at,
                updated_at: r.updated_at
              }
            end

        render json: { steps: rows }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][steps_by_session_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 steps: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02 — ACTION: upload
      # ROUTE: POST /api/claims/sessions/:session_id/upload
      # PURPOSE:
      # - Accept multipart pdfs[] (or pdfs/files/file fallbacks)
      # - Call service Claims::Ingest::UploadPdfs
      # - Return run report JSON for GUI troubleshooting
      # ============================================================

      def upload
        # ============================================================
        # SECTION 02.01 — INPUT PARSING
        # ============================================================

        session_id = params[:session_id].to_s

        files =
          Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:files]) + Array(params[:file])

        files = files.flatten.compact

        # ============================================================
        # SECTION 02.02 — SERVICE CALL
        # ============================================================

        result =
          ::Claims::Ingest::UploadPdfs.call(
            session_id: session_id,
            files: files
          )

        render json: result.to_h, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][upload] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 stage: "upload_pdfs",
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.05 — ACTION: upload_fix
      # ROUTE: POST /api/claims/invoices/:invoice_id/upload_fix
      # PURPOSE:
      # - Accept multipart pdfs[] (or pdfs/files/file fallbacks)
      # - Insert next invoice_version (+1) for an existing invoice
      # ============================================================

      def upload_fix
        invoice_id = params[:invoice_id].to_s

        files =
          Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:files]) + Array(params[:file])

        files = files.flatten.compact

        result =
          ::Claims::Ingest::UploadFixPdf.call(
            invoice_id: invoice_id,
            files: files
          )

        render json: result.to_h, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][upload_fix] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 stage: "upload_fix_pdf",
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.10 — ACTION: run_ocr
      # ROUTE: POST /api/claims/ingest/run_ocr
      # BODY: { invoice_version_id: "uuid", ingest_run_id?: "uuid" }
      # PURPOSE:
      # - enqueue Sidekiq job that calls Node /inv/ocr
      # - creates ingest_step_runs row inside the job
      # ============================================================
      def run_ocr
        invoice_version_id = params[:invoice_version_id].to_s.strip
        raise "Missing invoice_version_id" if invoice_version_id.empty?

        ingest_run_id = params[:ingest_run_id].to_s.strip
        ingest_run_id = nil if ingest_run_id.empty?

        validationgenai_ruleset_id =
          params[:validationgenai_ruleset_id].to_s.strip
        validationgenai_ruleset_id = nil if validationgenai_ruleset_id.empty?

        jid =
          ::Claims::RunOcrJob.perform_async(
            invoice_version_id,
            ingest_run_id,
            validationgenai_ruleset_id
          )

        render json: {
                 ok: true,
                 enqueued: true,
                 job_id: jid,
                 invoice_version_id: invoice_version_id,
                 ingest_run_id: ingest_run_id,
                 validationgenai_ruleset_id: validationgenai_ruleset_id
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][run_ocr] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.20 — ACTION: run_genai
      # ROUTE: POST /api/claims/ingest/run_genai
      # BODY: { session_id: "uuid", invoice_version_id: "uuid", validationgenai_ruleset_id?: "uuid", ingest_run_id?: "uuid" }
      # PURPOSE (milestone 1):
      # - enqueue Sidekiq job that calls Node /inv/genai
      # - job will create ingest_step_runs row (step_type='genai')
      # ============================================================
      def run_genai
        session_id = params[:session_id].to_s.strip
        raise "Missing session_id" if session_id.empty?

        invoice_version_id = params[:invoice_version_id].to_s.strip
        raise "Missing invoice_version_id" if invoice_version_id.empty?

        validationgenai_ruleset_id =
          params[:validationgenai_ruleset_id].to_s.strip
        validationgenai_ruleset_id = nil if validationgenai_ruleset_id.empty?

        mode = params[:mode].to_s.strip
        mode = "normal" if mode.empty?
        raise "Invalid mode" unless %w[normal classifier_only].include?(mode)

        ingest_run_id = params[:ingest_run_id].to_s.strip
        ingest_run_id = nil if ingest_run_id.empty?

        if validationgenai_ruleset_id.nil? && mode == "normal"
          validationgenai_ruleset_id = resolve_default_ruleset_id_for_run_genai!
        end

        jid =
          ::Claims::RunGenaiJob.perform_async(
            session_id,
            invoice_version_id,
            validationgenai_ruleset_id,
            ingest_run_id,
            mode
          )

        render json: {
                 ok: true,
                 enqueued: true,
                 job_id: jid,
                 session_id: session_id,
                 invoice_version_id: invoice_version_id,
                 validationgenai_ruleset_id: validationgenai_ruleset_id,
                 mode: mode,
                 ingest_run_id: ingest_run_id
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][run_genai] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.30 — ACTION: run_show
      # ROUTE: GET /api/claims/ingest/runs/:ingest_run_id
      # PURPOSE:
      # - Returns ingest run header details for run context strip
      # ============================================================
      def run_show
        ingest_run_id = params[:ingest_run_id].to_s.strip
        raise "Missing ingest_run_id." if ingest_run_id.empty?

        run = ::Claims::IngestRun.find(ingest_run_id)
        render json: {
                 id: run.id,
                 session_id: run.session_id,
                 status: run.status,
                 total_files: run.total_files,
                 completed_files: run.completed_files,
                 failed_files: run.failed_files,
                 messages: run.messages,
                 created_at: run.created_at,
                 updated_at: run.updated_at,
                 completed_at: run.completed_at
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][run_show] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.40 — ACTION: run_invoices_index
      # ROUTE: GET /api/claims/ingest/runs/:ingest_run_id/invoices
      # PURPOSE:
      # - Returns one row per invoice version touched in the ingest run
      # ============================================================
      def run_invoices_index
        ingest_run_id = params[:ingest_run_id].to_s.strip
        raise "Missing ingest_run_id." if ingest_run_id.empty?

        invoice_version_ids =
          ::Claims::IngestStepRun
            .where(ingest_run_id: ingest_run_id)
            .distinct
            .pluck(:invoice_version_id)

        versions =
          ::Claims::InvoiceVersion
            .joins(:invoice)
            .where(id: invoice_version_ids)
            .order(created_at: :asc)

        rows =
          versions.map do |iv|
            inv = iv.invoice
            {
              invoice_id: inv.id,
              invoice_status: inv.status,
              invoice_status_updated_at: inv.status_updated_at,
              invoice_version_id: iv.id,
              invoice_versionno: iv.invoice_versionno,
              original_filename: iv.original_filename,
              storage_key: iv.storage_key,
              created_at: iv.created_at,
              updated_at: iv.updated_at
            }
          end

        render json: { rows: rows }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][run_invoices_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.50 — ACTION: steps_by_invoice_index
      # ROUTE: GET /api/claims/ingest/invoices/:invoice_id/steps
      # PURPOSE:
      # - Returns all step history for an invoice (optional run filter)
      # ============================================================
      def steps_by_invoice_index
        invoice_id = params[:invoice_id].to_s.strip
        raise "Missing invoice_id." if invoice_id.empty?

        ingest_run_id = params[:ingest_run_id].to_s.strip
        ingest_run_id = nil if ingest_run_id.empty?

        limit = params[:limit].to_i
        limit = 200 if limit <= 0
        limit = 500 if limit > 500

        scope =
          ::Claims::IngestStepRun.joins(
            "JOIN claims.invoice_versions iv ON iv.id = claims.ingest_step_runs.invoice_version_id"
          ).where("iv.invoice_id = ?", invoice_id)

        scope = scope.where(ingest_run_id: ingest_run_id) if ingest_run_id

        rows =
          scope
            .order(created_at: :desc)
            .limit(limit)
            .map do |r|
              iv = ::Claims::InvoiceVersion.find_by(id: r.invoice_version_id)
              inv = iv&.invoice
              {
                id: r.id,
                ingest_run_id: r.ingest_run_id,
                session_id: r.session_id,
                invoice_id: invoice_id,
                invoice_version_id: r.invoice_version_id,
                invoice_versionno: iv&.invoice_versionno,
                original_filename: iv&.original_filename,
                invoice_status: inv&.status,
                step_type: r.step_type,
                status: r.status,
                error_text: r.error_text,
                validationgenai_ruleset_id: r.validationgenai_ruleset_id,
                created_at: r.created_at,
                updated_at: r.updated_at
              }
            end

        classifier_results =
          ::Claims::InvoiceVersionUpgradeType
            .joins(
              "JOIN claims.invoice_versions iv ON iv.id = claims.invoice_version_upgrade_types.invoice_version_id"
            )
            .joins(
              "JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
            )
            .select(
              "claims.invoice_version_upgrade_types.*",
              "iut.upgrade_type_key AS upgrade_type_key",
              "iut.description AS upgrade_type_description"
            )
            .where("iv.invoice_id = ?", invoice_id)
            .where(source_engine: "classifier")
            .order(updated_at: :desc)
            .map do |r|
              {
                id: r.id,
                invoice_version_id: r.invoice_version_id,
                invoice_upgrade_type_id: r.invoice_upgrade_type_id,
                upgrade_type_key: r.read_attribute("upgrade_type_key"),
                upgrade_type_description:
                  r.read_attribute("upgrade_type_description"),
                call_status: r.call_status,
                confidence: r.confidence,
                evidence_text: r.evidence_text,
                classifier_notes: r.classifier_notes,
                updated_at: r.updated_at
              }
            end

        render json: {
                 rows: rows,
                 classifier_results: classifier_results
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][steps_by_invoice_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.60 — ACTION: admin_submit_batch
      # ROUTE: POST /api/claims/ingest/admin_submit_batch
      # PURPOSE:
      # - Simulates full contractor submission flow for multiple files:
      #   create session (optional), upload each file, enqueue OCR->GenAI chain.
      # ============================================================
      def admin_submit_batch
        contractor_id = params[:contractor_id].to_s.strip
        submitter_id = params[:submitter_id].to_s.strip
        validationgenai_ruleset_id =
          params[:validationgenai_ruleset_id].to_s.strip
        validationgenai_ruleset_id =
          resolve_default_ruleset_id_for_run_genai! if validationgenai_ruleset_id.empty?

        raise "Missing contractor_id" if contractor_id.empty?
        raise "Missing submitter_id" if submitter_id.empty?

        files =
          Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:files]) + Array(params[:file])

        files = files.flatten.compact
        if files.empty?
          raise "No files received. Expected multipart field pdfs[] (or pdfs)."
        end

        session_result =
          ::Claims::Sessions::Create.call(contractor_id: contractor_id)
        session_id = session_result.session.id
        created_session = true

        now = Time.current
        ingest_run =
          ::Claims::IngestRun.create!(
            session_id: session_id,
            status: "queued",
            total_files: files.size,
            completed_files: 0,
            failed_files: 0,
            messages: [],
            created_at: now,
            updated_at: now
          )

        results = []

        files.each_with_index do |f, idx|
          name = file_safe_call(f, :original_filename) || "unknown.pdf"
          ctype = file_safe_call(f, :content_type) || "application/pdf"
          size = file_safe_call(f, :size)

          begin
            invoice = nil
            invoice_version = nil

            ActiveRecord::Base.transaction do
              invoice =
                ::Claims::Invoice.create!(
                  session_id: session_id,
                  contractor_id: contractor_id,
                  submitter_id: submitter_id,
                  status: "upload_in_progress",
                  status_updated_at: Time.current,
                  submitted_at: Time.current,
                  created_at: Time.current,
                  updated_at: Time.current
                )

              pending_key =
                "PENDING/session=#{session_id}/invoice=#{invoice.id}/v=1/#{SecureRandom.uuid}.pdf"

              invoice_version =
                ::Claims::InvoiceVersion.create!(
                  invoice_id: invoice.id,
                  invoice_versionno: 1,
                  storage_provider: "azure_blob",
                  storage_key: pending_key,
                  original_filename: name,
                  content_type: ctype,
                  byte_size: size,
                  created_at: Time.current,
                  updated_at: Time.current
                )
            end

            node_resp =
              ingest_node_upload_pdf!(
                session_id: session_id,
                invoice_version_id: invoice_version.id,
                file: f
              )

            final_storage_key = ingest_extract_storage_key(node_resp)

            if final_storage_key.to_s.strip.empty?
              raise "Node upload returned no storage_key"
            end

            ActiveRecord::Base.transaction do
              invoice.lock!
              invoice_version.lock!

              iv_update = {
                storage_key: final_storage_key,
                updated_at: Time.current
              }
              iv_update[:byte_size] = node_resp["byte_size"] if node_resp.key?(
                "byte_size"
              )
              iv_update[:sha256] = node_resp["sha256"] if node_resp.key?(
                "sha256"
              )

              invoice_version.update_columns(iv_update)

              invoice.update_columns(
                status: "ocr_queued",
                status_updated_at: Time.current,
                updated_at: Time.current
              )

              ::Claims::IngestStepRun.create!(
                ingest_run_id: ingest_run.id,
                session_id: session_id,
                invoice_version_id: invoice_version.id,
                step_type: "ocr",
                status: "queued",
                error_text: nil,
                created_at: Time.current,
                updated_at: Time.current
              )
            end

            jid =
              ::Claims::RunOcrJob.perform_async(
                invoice_version.id,
                ingest_run.id,
                validationgenai_ruleset_id
              )

            results << {
              index: idx + 1,
              original_filename: name,
              content_type: ctype,
              byte_size: size,
              status: "queued_ocr",
              job_id: jid,
              invoice_id: invoice.id,
              invoice_version_id: invoice_version.id,
              invoice_versionno: invoice_version.invoice_versionno
            }
          rescue => e
            begin
              if invoice
                failed_status =
                  (
                    if invoice.status.to_s.start_with?("upload_")
                      "upload_failed"
                    else
                      "ocr_failed"
                    end
                  )
                invoice.update!(
                  status: failed_status,
                  status_updated_at: Time.current
                )
              end
            rescue StandardError
              # ignore
            end

            begin
              if invoice_version&.id
                ::Claims::IngestStepRun.create!(
                  ingest_run_id: ingest_run.id,
                  session_id: session_id,
                  invoice_version_id: invoice_version.id,
                  step_type: "ocr",
                  status: "failed",
                  error_text: "ocr_enqueue_or_upload_failed: #{e.message}",
                  created_at: Time.current,
                  updated_at: Time.current
                )
              end
            rescue StandardError
              # ignore
            end

            results << {
              index: idx + 1,
              original_filename: name,
              content_type: ctype,
              byte_size: size,
              status: "failed",
              error: e.message,
              invoice_id: invoice&.id,
              invoice_version_id: invoice_version&.id
            }
          end
        end

        ::Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run.id)
        ingest_run.reload

        render json: {
                 ok: true,
                 ingest_run_id: ingest_run.id,
                 session_id: session_id,
                 created_session: created_session,
                 status: ingest_run.status,
                 total_files: ingest_run.total_files,
                 completed_files: ingest_run.completed_files,
                 failed_files: ingest_run.failed_files,
                 results: results
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][ingest][admin_submit_batch] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      private

      def resolve_default_ruleset_id_for_run_genai!
        row =
          ::Claims::ValidationgenaiRuleset
            .joins(
              "JOIN claims.invoice_upgrade_types iut ON iut.id = claims.validationgenai_rulesets.invoice_upgrade_type_id"
            )
            .where(
              "iut.upgrade_type_key = ? OR claims.validationgenai_rulesets.ruleset_shortname = ?",
              "common",
              "common"
            )
            .order(
              Arel.sql(
                "claims.validationgenai_rulesets.updated_at DESC, claims.validationgenai_rulesets.created_at DESC, claims.validationgenai_rulesets.id DESC"
              )
            )
            .first

        if row.nil?
          raise "No default/common validationgenai_ruleset found for full GenAI run."
        end

        row.id
      end

      def file_safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)
        obj.public_send(method_name)
      rescue StandardError
        nil
      end

      def ingest_node_upload_pdf!(session_id:, invoice_version_id:, file:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        base = base.sub(%r{/\z}, "")
        uri = URI("#{base}/inv/upload-pdf")

        req = Net::HTTP::Post.new(uri)

        io = File.open(file.path, "rb")
        filename =
          file_safe_call(file, :original_filename) || File.basename(file.path)
        content_type = file_safe_call(file, :content_type) || "application/pdf"

        form = [
          ["sessionId", session_id.to_s],
          ["invoiceVersionId", invoice_version_id.to_s],
          ["file", io, { filename: filename, content_type: content_type }]
        ]

        req.set_form(form, "multipart/form-data")

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Node upload failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      ensure
        io&.close
      end

      def ingest_extract_storage_key(node_resp)
        node_resp.fetch("storage_key")
      end
    end
  end
end
