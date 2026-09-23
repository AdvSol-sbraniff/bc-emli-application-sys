require "rails_helper"

RSpec.describe Claims::Invoices::DestroyPackage do
  describe ".call" do
    %i[model rule].each do |kind|
      it "deletes a #{kind}-comparison candidate and preserves the comparison history" do
        baseline = create_package
        candidate = create_package
        comparison = create_comparison(kind, baseline, candidate)

        described_class.call(invoice_id: candidate[:invoice].id)

        expect(Claims::Invoice.exists?(candidate[:invoice].id)).to be(false)
        expect(Claims::InvoiceVersion.exists?(candidate[:version].id)).to be(
          false
        )
        expect(Claims::IngestRun.exists?(candidate[:run].id)).to be(false)
        expect(Claims::InvoiceVersion.exists?(baseline[:version].id)).to be(
          true
        )
        expect(Claims::IngestRun.exists?(baseline[:run].id)).to be(true)
        expect(comparison.reload.candidate_invoice_version_id).to be_nil
        expect(comparison.candidate_ingest_run_id).to be_nil
        expect(comparison.status).to eq("completed")
        summary =
          kind == :model ? :upgrade_analysis_comparison : :rule_comparison
        expect(comparison.public_send(summary)).to eq("Accepted comparison")
        expect(comparison.test_run.reload.status).to eq("completed")
      end
    end

    it "protects a suite baseline with a readable error and leaves its package intact" do
      baseline = create_package
      create_comparison(:model, baseline, create_package)

      expect {
        described_class.call(invoice_id: baseline[:invoice].id)
      }.to raise_error(described_class::ReferencedByTest, /test-suite baseline/)
      expect(Claims::InvoiceVersion.exists?(baseline[:version].id)).to be(true)
      expect(Claims::IngestRun.exists?(baseline[:run].id)).to be(true)
    end

    it "protects a completed case while its parent comparison is still running" do
      candidate = create_package
      comparison = create_comparison(:model, create_package, candidate)
      comparison.test_run.update!(status: "running")

      expect {
        described_class.call(invoice_id: candidate[:invoice].id)
      }.to raise_error(described_class::ReferencedByTest, /active comparison/)
      expect(comparison.reload.candidate_invoice_version_id).to eq(
        candidate[:version].id
      )
      expect(Claims::IngestRun.exists?(candidate[:run].id)).to be(true)
    end

    it "protects an active case linked only through its ingest run" do
      candidate = create_package
      comparison = create_comparison(:model, create_package, candidate)
      comparison.update!(status: "running", candidate_invoice_version_id: nil)

      expect {
        described_class.call(invoice_id: candidate[:invoice].id)
      }.to raise_error(described_class::ReferencedByTest, /active comparison/)
      expect(comparison.reload.candidate_ingest_run_id).to eq(
        candidate[:run].id
      )
      expect(Claims::InvoiceVersion.exists?(candidate[:version].id)).to be(true)
    end

    it "rolls back released references if another comparison still needs the package" do
      candidate = create_package
      completed = create_comparison(:model, create_package, candidate)
      active = create_comparison(:rule, create_package, candidate)
      active.test_run.update!(status: "running")

      expect {
        described_class.call(invoice_id: candidate[:invoice].id)
      }.to raise_error(described_class::ReferencedByTest, /active comparison/)
      expect(completed.reload.candidate_invoice_version_id).to eq(
        candidate[:version].id
      )
      expect(completed.candidate_ingest_run_id).to eq(candidate[:run].id)
      expect(Claims::Invoice.exists?(candidate[:invoice].id)).to be(true)
    end

    it "protects regression evidence with a readable error" do
      baseline = create_package
      candidate = create_package
      comparison = create_comparison(:model, baseline, candidate)
      regression =
        Claims::TestRunRegression.create!(
          test_suite: comparison.test_run.test_suite,
          status: "completed",
          document_triage_deployment_name: "test-model",
          supporting_document_extraction_deployment_name: "test-model",
          upgrade_analysis_deployment_name: "test-model"
        )
      regression.test_cases.create!(
        test_suite_case: comparison.test_suite_case,
        status: "completed",
        invoice_version: candidate[:version],
        ingest_run: candidate[:run]
      )

      expect {
        described_class.call(invoice_id: candidate[:invoice].id)
      }.to raise_error(described_class::ReferencedByTest, /regression test/)
      expect(comparison.reload.candidate_invoice_version_id).to eq(
        candidate[:version].id
      )
      expect(Claims::IngestRun.exists?(candidate[:run].id)).to be(true)
    end

    it "deletes the explicitly owned ingest package with the invoice" do
      now = Time.zone.parse("2026-06-23 17:10:00")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "contractor_precheck",
          created_at: now,
          updated_at: now
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "current/invoice.pdf",
          original_filename: "Invoice.pdf",
          content_type: "application/pdf",
          created_at: now,
          updated_at: now
        )
      status_transition =
        Claims::InvoiceStatusTransition.create!(
          invoice_id: invoice.id,
          invoice_version_id: invoice_version.id,
          from_status: "contractor_precheck",
          to_status: "contractor_precheck",
          created_at: now
        )
      package_run =
        Claims::IngestRun.create!(
          run_kind: "initial_upload",
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          status: "succeeded",
          total_files: 1,
          completed_files: 1,
          failed_files: 0,
          resolved_invoice_version_id: invoice_version.id,
          created_at: now,
          updated_at: now,
          completed_at: now
        )
      package_document =
        Claims::IngestDocument.create!(
          ingest_run_id: package_run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: invoice_version.id,
          storage_provider: "azure_blob",
          storage_key: "current/invoice.pdf",
          original_filename: "Invoice.pdf",
          content_type: "application/pdf",
          document_kind: "invoice",
          created_at: now,
          updated_at: now
        )
      Claims::IngestStepRun.create!(
        ingest_run_id: package_document.ingest_run_id,
        session_id: session.id,
        ingest_document_id: package_document.id,
        step_type: "read_document",
        status: "succeeded",
        created_at: package_document.created_at,
        updated_at: package_document.updated_at
      )

      deleted = described_class.call(invoice_id: invoice.id)

      expect(deleted[:invoice_versions]).to eq(1)
      expect(deleted[:ingest_documents]).to eq(1)
      expect(deleted[:ingest_runs]).to eq(1)
      expect(deleted[:ingest_step_runs]).to eq(1)
      expect(deleted[:sessions]).to eq(1)
      expect(Claims::Invoice.exists?(invoice.id)).to be(false)
      expect(
        Claims::InvoiceStatusTransition.exists?(status_transition.id)
      ).to be(false)
      expect(Claims::Session.exists?(session.id)).to be(false)
      expect(Claims::IngestRun.where(session_id: session.id)).to be_empty
      expect(Claims::IngestDocument.where(session_id: session.id)).to be_empty
      expect(Claims::IngestStepRun.where(session_id: session.id)).to be_empty
    end
  end

  def create_package
    now = Time.current
    contractor =
      Contractor.create!(business_name: "Deletion #{SecureRandom.hex(4)}")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck",
        created_at: now,
        updated_at: now
      )
    version =
      Claims::InvoiceVersion.create!(
        invoice: invoice,
        invoice_versionno: 1,
        storage_key: "test/invoice.pdf",
        created_at: now,
        updated_at: now
      )
    run =
      Claims::IngestRun.create!(
        invoice: invoice,
        session_id: session.id,
        contractor_id: contractor.id,
        resolved_invoice_version: version,
        run_kind: "initial_upload",
        status: "succeeded",
        completed_at: now,
        created_at: now,
        updated_at: now
      )
    { invoice: invoice, version: version, run: run }
  end

  def create_comparison(kind, baseline, candidate)
    suite = Claims::TestSuite.create!(name: "Deletion #{SecureRandom.hex(4)}")
    suite_case =
      suite.test_suite_cases.create!(
        name: "Baseline",
        baseline_invoice_version: baseline[:version],
        baseline_ingest_run: baseline[:run]
      )
    parent_attributes = {
      test_suite: suite,
      status: "completed",
      comparison_deployment_name: "test-evaluator"
    }
    summaries =
      if kind == :model
        {
          document_classification_comparison: "Accepted classification",
          supporting_document_extraction_comparison: "Accepted extraction",
          upgrade_analysis_comparison: "Accepted comparison"
        }
      else
        { rule_comparison: "Accepted comparison" }
      end
    summaries.each { |key, value| parent_attributes["overall_#{key}"] = value }
    parent =
      if kind == :model
        Claims::TestRunModelCompare::DEPLOYMENT_ATTRIBUTES.each do |key|
          parent_attributes[key] ||= "test-model"
        end
        Claims::TestRunModelCompare.create!(parent_attributes)
      else
        rule =
          Claims::GenaiRule.create!(
            genai_rule_key: "delete_test_#{SecureRandom.hex(4)}",
            contractor_display_name: "Test rule",
            prompt_text: "Check evidence",
            source_quote: "Test requirement",
            enabled: true,
            contractor_visibility: "hidden",
            contractor_blocking_policy: "non_blocking",
            admin_workflow_policy: "not_managed"
          )
        Claims::TestRunRuleCompare.create!(
          parent_attributes.merge(candidate_rule: rule)
        )
      end
    parent.test_cases.create!(
      **summaries,
      test_suite_case: suite_case,
      status: "completed",
      baseline_invoice_version: baseline[:version],
      baseline_ingest_run: baseline[:run],
      candidate_invoice_version: candidate[:version],
      candidate_ingest_run: candidate[:run]
    )
  end
end
