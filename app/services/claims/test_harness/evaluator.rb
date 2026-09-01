# frozen_string_literal: true

module Claims
  module TestHarness
    class Evaluator
      MAX_EVIDENCE_CHARACTERS = 180_000

      def self.compare(domain:, baseline:, candidate:, deployment_name:)
        payload =
          call(
            deployment_name: deployment_name,
            system_text: <<~TEXT,
              You evaluate two AI processing results for a government invoice program.
              BASELINE is the human-reviewed, accepted answer key. Treat it as the expected
              result and assess whether CANDIDATE is materially equivalent to it.
              Compare accuracy, completeness, unsupported claims, traceability, and material
              business impact. Be direct and evidence based. Reply as strict JSON with one
              string field named summary. Do not penalize harmless wording or formatting
              differences. If candidate evidence suggests the baseline may be wrong, flag the
              discrepancy for human review rather than silently preferring the candidate.
            TEXT
            user_text: <<~TEXT
              Comparison domain: #{domain.to_s.humanize}

              BASELINE
              #{bounded_json(baseline)}

              CANDIDATE
              #{bounded_json(candidate)}
            TEXT
          )
        extract_text(payload, "summary")
      end

      def self.finalize_model(case_rows:, deployment_name:)
        call(
          deployment_name: deployment_name,
          system_text: <<~TEXT,
            You summarize a completed suite-wide model comparison for government administrators.
            Synthesize material patterns across cases, noting improvements, regressions, and
            uncertainty. Reply as strict JSON with exactly three string fields:
            document_classification, supporting_document_extraction, and upgrade_analysis.
          TEXT
          user_text:
            bounded_json(
              case_rows.map do |row|
                {
                  case_name: row.test_suite_case.name,
                  document_classification:
                    row.document_classification_comparison,
                  supporting_document_extraction:
                    row.supporting_document_extraction_comparison,
                  upgrade_analysis: row.upgrade_analysis_comparison
                }
              end
            )
        ).then do |payload|
          {
            overall_document_classification_comparison:
              extract_text(payload, "document_classification"),
            overall_supporting_document_extraction_comparison:
              extract_text(payload, "supporting_document_extraction"),
            overall_upgrade_analysis_comparison:
              extract_text(payload, "upgrade_analysis")
          }
        end
      end

      def self.finalize_rule(case_rows:, deployment_name:)
        payload =
          call(
            deployment_name: deployment_name,
            system_text: <<~TEXT,
              You summarize a suite-wide comparison of accepted baseline evidence with fresh
              results from the current definition of one government program rule. Identify
              material improvements, regressions, consistency, and uncertainty.
              Reply as strict JSON with one string field named summary.
            TEXT
            user_text:
              bounded_json(
                case_rows.map do |row|
                  {
                    case_name: row.test_suite_case.name,
                    comparison: row.rule_comparison
                  }
                end
              )
          )
        extract_text(payload, "summary")
      end

      def self.call(deployment_name:, system_text:, user_text:)
        ::Claims::Genai::NodeClient.call(
          deployment_name: deployment_name,
          contextwindowjson: [
            {
              role: "system",
              content: [{ type: "input_text", text: system_text.strip }]
            },
            {
              role: "user",
              content: [{ type: "input_text", text: user_text.to_s }]
            }
          ],
          diagnostic_context: {
            step_type: "test_harness_comparison"
          }
        )
      end

      def self.extract_text(payload, key)
        value = payload[key] || payload[key.to_sym]
        value = value.to_s.strip
        raise "Comparison model returned no #{key}." if value.blank?

        value
      end

      def self.bounded_json(value)
        value.to_json.first(MAX_EVIDENCE_CHARACTERS)
      end
      private_class_method :call, :extract_text, :bounded_json
    end
  end
end
