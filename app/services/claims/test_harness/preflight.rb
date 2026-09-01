# frozen_string_literal: true

module Claims
  module TestHarness
    class Preflight
      RUN_DEPLOYMENTS = %i[
        document_triage_deployment_name
        supporting_document_extraction_deployment_name
        upgrade_analysis_deployment_name
      ].freeze

      def self.suite!(suite)
        cases =
          suite
            .test_suite_cases
            .includes(baseline_ingest_run: :ingest_documents)
            .order(:name)
            .to_a
        raise ArgumentError, "The test suite has no cases." if cases.empty?

        cases.each do |test_case|
          run = test_case.baseline_ingest_run
          unless run.status == "succeeded"
            raise ArgumentError,
                  "#{test_case.name}: baseline ingest run did not succeed."
          end
          unless run.resolved_invoice_version_id ==
                   test_case.baseline_invoice_version_id
            raise ArgumentError,
                  "#{test_case.name}: baseline version was not produced by its selected ingest run."
          end
          if run.ingest_documents.none?
            raise ArgumentError,
                  "#{test_case.name}: baseline run has no source package."
          end
        end
        cases
      end

      def self.model_compare!(suite)
        cases = suite!(suite)
        reference = deployment_values(cases.first.baseline_ingest_run)
        missing =
          RUN_DEPLOYMENTS.select { |attribute| reference[attribute].blank? }
        if missing.any?
          raise ArgumentError,
                "#{cases.first.name}: baseline run is missing #{missing.map { |v| v.to_s.humanize }.to_sentence}."
        end

        cases
          .drop(1)
          .each do |test_case|
            values = deployment_values(test_case.baseline_ingest_run)
            next if values == reference

            raise ArgumentError,
                  "#{test_case.name}: baseline models do not match the rest of the suite."
          end
        [cases, reference]
      end

      def self.rule_compare!(suite:, candidate_rule:)
        cases = suite!(suite)
        rule_key = candidate_rule.genai_rule_key
        cases.each do |test_case|
          version = test_case.baseline_invoice_version
          unless version
                   .rulechecks
                   .where(source_engine: "genai", rule_key: rule_key)
                   .exists?
            raise ArgumentError,
                  "#{test_case.name}: baseline version did not evaluate #{rule_key}."
          end

          missing =
            RUN_DEPLOYMENTS.select do |attribute|
              test_case.baseline_ingest_run.public_send(attribute).blank?
            end
          if missing.any?
            raise ArgumentError,
                  "#{test_case.name}: baseline run is missing model provenance."
          end
        end
        cases
      end

      def self.deployment_values(run)
        RUN_DEPLOYMENTS.index_with do |attribute|
          run.public_send(attribute).to_s
        end
      end
    end
  end
end
