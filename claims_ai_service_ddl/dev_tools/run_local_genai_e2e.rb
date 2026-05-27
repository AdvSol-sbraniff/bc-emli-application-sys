# frozen_string_literal: true

# Local/dev harness for exercising the full GenAI validation runtime from a
# bundled Document Intelligence JSON sample.
#
# Usage from the app container:
#   bin/rails runner claims_ai_service_ddl/dev_tools/run_local_genai_e2e.rb
#
# Optional env overrides:
#   DI_JSON_PATH=/app/claims_ai_service_documentation/pdf\ test\ files/brown\ output-di-call.json
#   ELIGIBILITY_CODE="ESPI - 7a1899b2"
#   CONTRACTOR_ID=<uuid>
#   USER_ID=<uuid>

require "json"

di_json_path =
  ENV["DI_JSON_PATH"].presence ||
    "/app/claims_ai_service_documentation/pdf test files/brown output-di-call.json"
eligibility_code = ENV["ELIGIBILITY_CODE"].presence || "ESPI - 7a1899b2"

abort "DI JSON file not found: #{di_json_path}" unless File.exist?(di_json_path)

contractor =
  if ENV["CONTRACTOR_ID"].present?
    Contractor.find(ENV["CONTRACTOR_ID"])
  else
    Contractor.order(:created_at, :id).first
  end
abort "No contractor row found." unless contractor

user =
  if ENV["USER_ID"].present?
    User.find(ENV["USER_ID"])
  else
    User.order(:created_at, :id).first
  end
abort "No user row found." unless user

di_json = JSON.parse(File.read(di_json_path))
now = Time.current

elig =
  Claims::UsersEligibilitycode.find_or_create_by!(eligibility_code: eligibility_code) do |row|
    row.user_id = user.id
    row.applied_at = now - 30.days
    row.approved_at = now - 25.days
    row.expires_at = now + 180.days
    row.created_at = now
    row.updated_at = now
  end

session =
  Claims::Session.create!(
    created_at: now,
    updated_at: now
  )

invoice =
  Claims::Invoice.create!(
    session_id: session.id,
    contractor_id: contractor.id,
    submitter_id: user.id,
    status: "ocr_complete",
    status_updated_at: now,
    submitted_at: now,
    created_at: now,
    updated_at: now
  )

invoice_version =
  Claims::InvoiceVersion.create!(
    invoice_id: invoice.id,
    invoice_versionno: 1,
    storage_key: "local-e2e/#{SecureRandom.uuid}.pdf",
    original_filename: "brownlow-sample.pdf",
    content_type: "application/pdf",
    di_raw_json: di_json,
    created_at: now,
    updated_at: now
  )

common_ruleset =
  Claims::ValidationgenaiRuleset
    .joins(
      "JOIN claims.invoice_upgrade_types iut ON iut.id = claims.validationgenai_rulesets.invoice_upgrade_type_id"
    )
    .where("iut.upgrade_type_key = ?", "common")
    .order(Arel.sql("claims.validationgenai_rulesets.updated_at DESC, claims.validationgenai_rulesets.created_at DESC, claims.validationgenai_rulesets.id DESC"))
    .first

abort "No common runtime ruleset found." if common_ruleset.nil?

Claims::RunGenaiJob.new.perform(
  session.id,
  invoice_version.id,
  common_ruleset.id,
  nil,
  "normal"
)

invoice_version.reload

puts "session_id=#{session.id}"
puts "invoice_id=#{invoice.id}"
puts "invoice_version_id=#{invoice_version.id}"
puts "eligibility_code_id=#{elig.id}"
puts "genai_result=#{invoice_version.genai_result}"
puts "genai_overall_confidence=#{invoice_version.genai_overall_confidence}"
puts

detected =
  Array(
    invoice_version.genai_raw_json&.dig("classifier", "detected_upgrade_types")
  ).map { |row| row["upgrade_type_key"] }

puts "detected_upgrade_types=#{detected.join(", ")}"
puts

Claims::InvoiceVersionUpgradeType
  .joins(
    "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
  )
  .where(invoice_version_id: invoice_version.id, source_engine: "genai")
  .select(
    "claims.invoice_version_upgrade_types.*",
    "iut.upgrade_type_key AS upgrade_type_key"
  )
  .order(:created_at)
  .each do |row|
    ruleset =
      Claims::ValidationgenaiRuleset.find_by(id: row.validationgenai_ruleset_id)

    puts [
           row.read_attribute("upgrade_type_key"),
           row.result,
           row.confidence,
           row.validationgenai_ruleset_id,
           ruleset&.ruleset_shortname
         ].join(" | ")
  end

puts
puts "genai_rulechecks=#{Claims::InvoiceVersionRulecheck.where(invoice_version_id: invoice_version.id, source_engine: 'genai').count}"
puts "genai_located_fields=#{Claims::InvoiceVersionLocatedField.where(invoice_version_id: invoice_version.id, source_engine: 'genai').count}"
puts "code_located_fields=#{Claims::InvoiceVersionLocatedField.where(invoice_version_id: invoice_version.id, source_engine: 'code').count}"
