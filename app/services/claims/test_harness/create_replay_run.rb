# frozen_string_literal: true

module Claims
  module TestHarness
    class CreateReplayRun
      def self.call(
        baseline_ingest_run:,
        deployments:,
        harness_case: nil,
        ingest_run_pointer: nil
      )
        new(
          baseline_ingest_run: baseline_ingest_run,
          deployments: deployments,
          harness_case: harness_case,
          ingest_run_pointer: ingest_run_pointer
        ).call
      end

      def initialize(
        baseline_ingest_run:,
        deployments:,
        harness_case:,
        ingest_run_pointer:
      )
        @baseline_run = baseline_ingest_run
        @deployments = deployments.symbolize_keys
        @harness_case = harness_case
        @ingest_run_pointer = ingest_run_pointer
      end

      def call
        validate!
        now = Time.current
        session = nil
        invoice = nil
        run = nil
        cloned_documents = []

        ::Claims::IngestRun.transaction do
          if @harness_case
            @harness_case.lock!
            existing_run_id =
              @harness_case.public_send(@ingest_run_pointer).presence
            if existing_run_id
              run = ::Claims::IngestRun.find(existing_run_id)
              next
            end
          end

          session =
            ::Claims::Sessions::Create.call(
              contractor_id: @baseline_run.contractor_id
            ).session

          invoice =
            ::Claims::Invoice.create!(
              session_id: session.id,
              contractor_id: @baseline_run.contractor_id,
              submitter_id: nil,
              status: "contractor_precheck",
              status_updated_at: now,
              submitted_at: nil,
              created_at: now,
              updated_at: now
            )

          run =
            ::Claims::IngestRun.create!(
              session_id: session.id,
              contractor_id: @baseline_run.contractor_id,
              invoice_id: invoice.id,
              run_kind: "initial_upload",
              status: "queued",
              cleanup_failed_invoice_artifacts: false,
              total_files: source_documents.size,
              completed_files: 0,
              failed_files: 0,
              document_triage_deployment_name:
                @deployments.fetch(:document_triage_deployment_name),
              supporting_document_extraction_deployment_name:
                @deployments.fetch(
                  :supporting_document_extraction_deployment_name
                ),
              upgrade_analysis_deployment_name:
                @deployments.fetch(:upgrade_analysis_deployment_name),
              created_at: now,
              updated_at: now
            )

          ::Claims::IngestStepRun.create!(
            ingest_run_id: run.id,
            session_id: session.id,
            step_type: "stage_package",
            status: "succeeded",
            error_text: nil,
            created_at: now,
            updated_at: now
          )

          cloned_documents =
            source_documents.map do |source|
              document =
                ::Claims::IngestDocument.create!(
                  ingest_run_id: run.id,
                  session_id: session.id,
                  contractor_id: @baseline_run.contractor_id,
                  invoice_id: invoice.id,
                  resolved_invoice_id: invoice.id,
                  storage_provider: source.storage_provider,
                  storage_key: source.storage_key,
                  original_filename: source.original_filename,
                  content_type: source.content_type,
                  byte_size: source.byte_size,
                  sha256: source.sha256,
                  classification_confidence: 0,
                  document_kind_confidence: 0,
                  created_at: now,
                  updated_at: now
                )
              ::Claims::IngestStepRun.create!(
                ingest_run_id: run.id,
                session_id: session.id,
                ingest_document_id: document.id,
                step_type: "read_document",
                status: "queued",
                error_text: nil,
                created_at: now,
                updated_at: now
              )
              document
            end

          if @harness_case && @ingest_run_pointer
            @harness_case.update!(@ingest_run_pointer => run.id)
          end
        end

        return run if cloned_documents.empty?

        cloned_documents.each do |document|
          ::Claims::RunIngestReadOcrJob.perform_async(document.id, run.id)
        end
        ::Claims::Ingest::RunTransition.mark_running!(
          run: run,
          total_files: cloned_documents.size
        )
        ::Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)
        run
      end

      private

      def source_documents
        @source_documents ||=
          ::Claims::IngestDocument
            .where(ingest_run_id: @baseline_run.id)
            .order(:created_at, :id)
            .to_a
      end

      def validate!
        if @harness_case &&
             !%i[candidate_ingest_run_id ingest_run_id].include?(
               @ingest_run_pointer
             )
          raise ArgumentError, "Unsupported harness ingest-run pointer."
        end

        unless @baseline_run.status == "succeeded"
          raise ArgumentError, "Baseline ingest run must have succeeded."
        end
        if source_documents.empty?
          raise ArgumentError, "Baseline ingest run has no source documents."
        end

        if source_documents.any? { |document| document.storage_key.blank? }
          raise ArgumentError,
                "Baseline package has a document without an Azure storage key."
        end

        %i[
          document_triage_deployment_name
          supporting_document_extraction_deployment_name
          upgrade_analysis_deployment_name
        ].each do |attribute|
          if @deployments[attribute].to_s.strip.blank?
            raise ArgumentError, "#{attribute.to_s.humanize} is required."
          end
        end
      end
    end
  end
end
