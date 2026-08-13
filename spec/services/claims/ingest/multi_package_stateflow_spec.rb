require "rails_helper"
require "digest"

RSpec.describe "Claims ingest multi-package state flow" do
  package_type =
    Struct.new(
      :label,
      :directory,
      :invoice_filename,
      :upgrade_type_keys,
      :inject_retry,
      keyword_init: true
    )

  packages = [
    package_type.new(
      label: "demo1 ASHP wood and ventilation",
      directory: "demo1_aug4_ASHP-WOOD_VENT",
      invoice_filename: "01_Mini_Home_Energy_Solutions_Invoice.pdf",
      upgrade_type_keys: %w[air_source_heat_pump_wood ventilation],
      inject_retry: true
    ),
    package_type.new(
      label: "demo2 ASHP gas and health safety",
      directory: "demo2_aug4_ASHP-GAS_HS",
      invoice_filename: "01_Minime_Contracting_Company_Invoice.pdf",
      upgrade_type_keys: %w[
        air_source_heat_pump_gas_propane
        health_and_safety_remediation
      ]
    ),
    package_type.new(
      label: "demo3 electrical service upgrade fix",
      directory: "demo3_aug7_ESU",
      invoice_filename: "invoice_c1_fixed.PDF",
      upgrade_type_keys: %w[electrical_service_upgrade]
    ),
    package_type.new(
      label: "demo4 heat pump water heater",
      directory: "demo4_aug11_HPWH",
      invoice_filename: "01_MiniMe_Heat_Pump_Water_Heater_Invoice.pdf",
      upgrade_type_keys: %w[heat_pump_water_heater]
    )
  ].freeze

  before do
    allow(Claims::RunIngestReadOcrJob).to receive(:perform_async).and_return(
      "read-job"
    )
    allow(Claims::RunIngestTriageJob).to receive(:perform_async).and_return(
      "triage-job"
    )
    allow(Claims::RunSupportingDocumentTypeExtractionJob).to receive(
      :perform_async
    ).and_return("support-job")
    allow(Claims::RunOcrJob).to receive(:perform_async).and_return("ocr-job")
    allow(Claims::RunGenaiJob).to receive(:perform_async).and_return(
      "genai-job"
    )
    allow(Claims::FinalizeGenaiValidationJob).to receive(
      :perform_async
    ).and_return("finalize-job")
    allow(Claims::Ingest::UploadEvidenceFileToNode).to receive(:call) do |args|
      file = args.fetch(:file)
      {
        "storage_key" =>
          "stateflow/#{args.fetch(:upload_scope_id)}/#{file.original_filename}",
        "byte_size" => file.size,
        "sha256" => Digest::SHA256.file(file.path).hexdigest
      }
    end
  end

  packages.each do |package|
    it "completes #{package.label} through the canonical lifecycle" do
      contractor =
        Contractor.create!(business_name: "Stateflow #{package.label}")
      support_type =
        Claims::SupportingDocumentType.create!(
          type_key: "stateflow_#{SecureRandom.hex(6)}",
          description: "Stateflow catchall without extracted fields"
        )
      upgrade_types =
        package.upgrade_type_keys.map do |key|
          Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: key)
        end
      common = Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
      files = uploaded_files(package)

      result =
        Claims::Ingest::CreateDraftBatch.call(
          contractor_id: contractor.id,
          files: files,
          log_prefix: "multi_package_stateflow_spec"
        )
      run = Claims::IngestRun.find(result.fetch(:ingest_run_id))
      documents = Claims::IngestDocument.where(ingest_run_id: run.id).to_a
      expect(run.status).to eq("running")
      expect(documents.size).to eq(files.size)

      succeed_document_read!(run, documents)
      Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)
      classify_documents!(
        run: run,
        documents: documents,
        invoice_filename: package.invoice_filename,
        upgrade_type_keys: package.upgrade_type_keys,
        support_type: support_type
      )
      Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

      invoice_version =
        Claims::InvoiceVersion.find(run.reload.resolved_invoice_version_id)
      invoice_version.update!(di_raw_json: { "documents" => [] })
      succeed_step!(
        run: run,
        invoice_version: invoice_version,
        step_type: "extract_invoice"
      )
      Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

      case_facts =
        Claims::IngestStepRun.find_by!(
          ingest_run_id: run.id,
          invoice_version_id: invoice_version.id,
          step_type: "case_facts"
        )
      if package.inject_retry
        case_facts.update!(
          status: "failed",
          error_text: "Injected malformed first response",
          retryable: true,
          failure_category: "technical_failure",
          failure_code: "genai_service_malformed_response"
        )
        Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)
        presented =
          Claims::Ingest::ContractorRunPresenter.call(
            run: run.reload,
            contractor_id: contractor.id
          )
        expect(presented.fetch(:presentation_state)).to eq("processing")
        case_facts =
          Claims::Ingest::StepClaim.call(
            ingest_run_id: run.id,
            session_id: run.session_id,
            invoice_version_id: invoice_version.id,
            step_type: "case_facts"
          )
      end
      case_facts.update!(
        status: "succeeded",
        genai_results_json: {
          "case_facts" => {
          }
        },
        error_text: nil
      )

      create_succeeded_ruleset!(
        run,
        invoice_version,
        common,
        "evaluate_genai_ruleset"
      )
      upgrade_types.each do |upgrade_type|
        create_succeeded_ruleset!(
          run,
          invoice_version,
          upgrade_type,
          "evaluate_genai_ruleset"
        )
      end
      Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)
      aggregate =
        Claims::IngestStepRun.find_by!(
          ingest_run_id: run.id,
          invoice_version_id: invoice_version.id,
          step_type: "finalize_validation"
        )
      aggregate.update!(
        status: "succeeded",
        genai_results_json: {
          "contractor_advice_present" => true
        }
      )
      Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)
      Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

      expect(run.reload).to have_attributes(
        status: "succeeded",
        total_files: files.size,
        completed_files: files.size,
        failed_files: 0,
        pipeline_error_code: nil,
        pipeline_error_description: nil
      )
      expect(run.completed_at).to be_present
      expect(invoice_version.invoice.reload.status).to eq("contractor_precheck")
      expect(
        Claims::Ingest::ContractorRunPresenter.call(
          run: run,
          contractor_id: contractor.id
        ).fetch(:presentation_state)
      ).to eq("ready")
      expect(
        Claims::Ingest::StepOutcome.for_target(
          ingest_run_id: run.id,
          invoice_version_id: invoice_version.id,
          step_type: "case_facts"
        ).succeeded?
      ).to be(true)
    ensure
      files&.each(&:close)
    end
  end

  def uploaded_files(package)
    directory =
      Rails.root.join(
        "claims_ai_service_documentation",
        "Test Data",
        package.directory
      )
    filenames =
      if package.directory == "demo3_aug7_ESU"
        [
          package.invoice_filename,
          "MiniHome_home_comfort_handover_2026-07-25.pdf"
        ]
      else
        Dir
          .children(directory)
          .select { |name| File.file?(directory.join(name)) }
          .reject { |name| name.end_with?(".md") }
          .sort
      end

    filenames.map do |filename|
      path = directory.join(filename)
      mime =
        filename.downcase.end_with?(".pdf") ? "application/pdf" : "image/jpeg"
      Rack::Test::UploadedFile.new(path, mime)
    end
  end

  def succeed_document_read!(run, documents)
    documents.each do |document|
      document.update!(
        di_read_raw_json: {
          "content" => document.original_filename
        }
      )
      Claims::IngestStepRun.find_by!(
        ingest_run_id: run.id,
        ingest_document_id: document.id,
        step_type: "read_document"
      ).update!(status: "succeeded", error_text: nil)
    end
  end

  def classify_documents!(
    run:,
    documents:,
    invoice_filename:,
    upgrade_type_keys:,
    support_type:
  )
    documents.each do |document|
      invoice = document.original_filename == invoice_filename
      payload =
        if invoice
          {
            "document_kind" => "invoice",
            "document_kind_confidence" => 99,
            "detected_upgrade_types" =>
              upgrade_type_keys.map do |key|
                {
                  "upgrade_type_key" => key,
                  "confidence" => 99,
                  "evidence_text" => "Stateflow package evidence"
                }
              end
          }
        else
          {
            "document_kind" => "supporting_document",
            "document_kind_confidence" => 99
          }
        end
      document.update!(
        classifier_raw_json: payload,
        document_kind: invoice ? "invoice" : "supporting_document",
        document_kind_confidence: 99,
        document_kind_reason: "Stateflow test classification",
        supporting_document_type_id: invoice ? nil : support_type.id,
        classification_confidence: 99,
        classification_reason: "Stateflow test classification",
        classified_at: Time.current
      )
      Claims::IngestStepRun.find_by!(
        ingest_run_id: run.id,
        ingest_document_id: document.id,
        step_type: "classify_document"
      ).update!(status: "succeeded", genai_results_json: payload)
    end
  end

  def succeed_step!(run:, invoice_version:, step_type:)
    Claims::IngestStepRun.find_by!(
      ingest_run_id: run.id,
      invoice_version_id: invoice_version.id,
      step_type: step_type
    ).update!(status: "succeeded", error_text: nil)
  end

  def create_succeeded_ruleset!(run, invoice_version, upgrade_type, step_type)
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: run.session_id,
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type.id,
      step_type: step_type,
      status: "succeeded",
      genai_results_json: {
      }
    )
  end
end
