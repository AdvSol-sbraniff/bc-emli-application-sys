# frozen_string_literal: true

# Local/dev harness for rerunning deterministic claim invoice rulechecks.
#
# Usage from the app container:
#   bin/rails runner claims_ai_service_ddl/dev_tools/run_local_code_rulechecks.rb
#
# Optional target:
#   INVOICE_VERSION_ID=<uuid> bin/rails runner claims_ai_service_ddl/dev_tools/run_local_code_rulechecks.rb
#
# What it does:
# - Finds the invoice version.
# - Rebuilds code-located DB facts from an explicit or classifier-derived eligibility code.
# - Replaces source_engine='code' rulechecks for that invoice version.
# - Prints the resulting code rulecheck table.

invoice_version_id = ENV["INVOICE_VERSION_ID"].presence

invoice_version =
  if invoice_version_id
    Claims::InvoiceVersion.find(invoice_version_id)
  else
    Claims::InvoiceVersion.order(updated_at: :desc).first
  end

abort "No claims.invoice_versions row found." unless invoice_version

invoice = Claims::Invoice.find(invoice_version.invoice_id)
session = Claims::Session.find(invoice.session_id)

latest_classifier_payload =
  Claims::IngestStepRun
    .where(
      invoice_version_id: invoice_version.id,
      step_type: "classifier",
      status: "succeeded"
    )
    .order(updated_at: :desc)
    .limit(1)
    .pluck(:genai_results_json)
    .first

classifier_eligibility_code =
  ENV["ELIGIBILITY_CODE"].presence ||
    latest_classifier_payload&.dig("eligibility_code")

case_facts =
  Claims::GenaiCaseFacts::Build.call(
    sess: session,
    eligibility_code: classifier_eligibility_code
  )

Claims::GenaiCaseFacts::Build.persist_code_located_fields!(
  invoice_version_id: invoice_version.id,
  case_facts: case_facts,
  classifier_eligibility_code: classifier_eligibility_code
)

result =
  Claims::InvoiceVersionRulechecks::ApplyCodeRulechecks.call(
    invoice_version_id: invoice_version.id
  )

puts "invoice_version_id=#{invoice_version.id}"
puts "invoice_id=#{invoice.id}"
puts "session_id=#{session.id}"
puts "result=#{result.inspect}"
puts

Claims::InvoiceVersionRulecheck
  .where(invoice_version_id: invoice_version.id, source_engine: "code")
  .order(:rule_number)
  .pluck(:rule_number, :rule_key, :rule_result, :confidence, :observed_text)
  .each do |rule_number, rule_key, pass_flag, confidence, observed|
    status = pass_flag ? "PASS" : "FAIL"
    puts [
           rule_number.to_s.rjust(4),
           status.ljust(7),
           "conf=#{confidence.to_i.to_s.rjust(3)}",
           rule_key,
           observed
         ].join(" | ")
  end
