require "rails_helper"

RSpec.describe Claims::InvoiceVersionRulechecks::ApplyCodeRulechecks do
  let(:now) { Time.zone.parse("2026-06-24 09:00:00") }

  def invoice_upgrade_type(key)
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: key
    ) do |row|
      row.description = key.titleize
      row.created_at = now
      row.updated_at = now
    end
  end

  def enable_common_code_rule(rule_key)
    common_upgrade_type = invoice_upgrade_type("common")
    code_rule =
      Claims::CodeRule.find_or_create_by!(code_rule_key: rule_key) do |row|
        row.description = "test"
        row.enabled = true
        row.created_at = now
        row.updated_at = now
      end
    code_rule.update_columns(enabled: true, updated_at: now)
    Claims::CodeRuleUpgradeType.find_or_create_by!(
      code_rule: code_rule,
      invoice_upgrade_type: common_upgrade_type
    ) { |row| row.created_at = now }
  end

  def create_invoice_version(
    participant:,
    contractor:,
    invoice: nil,
    status: "genai_in_progress",
    version_number: 1
  )
    unless invoice
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: status,
          created_at: now,
          updated_at: now
        )
    end

    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: version_number,
      storage_key: "invoice-#{SecureRandom.hex(4)}.pdf",
      participant_user_id: participant.id,
      created_at: now,
      updated_at: now
    )
  end

  def add_upgrade_type(invoice_version, upgrade_type_key)
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: invoice_upgrade_type(upgrade_type_key).id,
      source_engine: "classifier",
      call_status: "classified",
      confidence: 100,
      created_at: now,
      updated_at: now
    )
  end

  describe ".call" do
    describe "submission_within_six_months" do
      def create_submission_deadline_version(
        program_received_at:,
        invoice_date:,
        submitted_at: nil
      )
        participant = create(:user)
        contractor =
          Contractor.create!(business_name: "Deadline Test Contractor")
        invoice =
          Claims::Invoice.create!(
            session_id:
              Claims::Session.create!(
                created_at: program_received_at,
                updated_at: program_received_at
              ).id,
            contractor_id: contractor.id,
            status: "genai_in_progress",
            submitted_at: submitted_at,
            created_at: program_received_at,
            updated_at: program_received_at
          )
        invoice_version =
          create_invoice_version(
            participant: participant,
            contractor: contractor,
            invoice: invoice
          )
        invoice_version.update!(di_ocr_invoice_date: invoice_date)
        invoice_version
      end

      def submission_deadline_rulecheck(invoice_version)
        described_class.call(invoice_version_id: invoice_version.id)
        Claims::InvoiceVersionRulecheck.find_by!(
          invoice_version_id: invoice_version.id,
          rule_key: "submission_within_six_months"
        )
      end

      before { enable_common_code_rule("submission_within_six_months") }

      it "passes using initial program receipt even when submitted_at is later" do
        invoice_version =
          create_submission_deadline_version(
            program_received_at: Time.zone.parse("2026-06-30 23:50:00"),
            invoice_date: Date.new(2026, 1, 1),
            submitted_at: Time.zone.parse("2027-04-01 09:00:00")
          )

        rulecheck = submission_deadline_rulecheck(invoice_version)

        expect(rulecheck.rule_result).to eq("pass")
        expect(rulecheck.calculation).to eq(
          "2026-01-01 + 6 months = 2026-07-01; 2026-06-30 <= 2026-07-01 => true"
        )
        expect(rulecheck.evidence_text).to eq(
          "invoice_versions.di_ocr_invoice_date + claims.invoices.created_at"
        )
      end

      it "fails when initial program receipt is after six months" do
        invoice_version =
          create_submission_deadline_version(
            program_received_at: Time.zone.parse("2026-07-02 00:01:00"),
            invoice_date: Date.new(2026, 1, 1)
          )

        rulecheck = submission_deadline_rulecheck(invoice_version)

        expect(rulecheck.rule_result).to eq("fail")
        expect(rulecheck.calculation).to eq(
          "2026-01-01 + 6 months = 2026-07-01; 2026-07-02 <= 2026-07-01 => false"
        )
      end

      it "warns when the invoice date is missing" do
        invoice_version =
          create_submission_deadline_version(
            program_received_at: Time.zone.parse("2026-06-30 23:50:00"),
            invoice_date: nil
          )

        rulecheck = submission_deadline_rulecheck(invoice_version)

        expect(rulecheck.rule_result).to eq("warn")
        expect(rulecheck.evidence_text).to eq(
          "Missing invoice date, so the six-month program receipt deadline cannot be calculated."
        )
      end
    end

    it "uses approval date plus six months instead of the stored eligibility expiry date" do
      enable_common_code_rule("eligibility_code_valid_for_invoice_date")

      participant = create(:user)
      eligibility_code =
        Claims::UsersEligibilitycode.create!(
          user: participant,
          eligibility_code: "ESP1-TEST-#{SecureRandom.hex(4)}",
          applied_at: Date.new(2026, 1, 1),
          approved_at: Date.new(2026, 1, 15),
          expires_at: Date.new(2030, 1, 15),
          created_at: now,
          updated_at: now
        )
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_in_progress",
          created_at: now,
          updated_at: now
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_key: "invoice.pdf",
          di_ocr_invoice_date: Date.new(2026, 8, 16),
          users_eligibilitycode_id: eligibility_code.id,
          participant_user_id: participant.id,
          created_at: now,
          updated_at: now
        )

      result = described_class.call(invoice_version_id: invoice_version.id)

      expect(result[:ok]).to be(true)
      rulecheck =
        Claims::InvoiceVersionRulecheck.find_by!(
          invoice_version_id: invoice_version.id,
          rule_key: "eligibility_code_valid_for_invoice_date"
        )
      expect(rulecheck.rule_result).to eq("fail")
      expect(rulecheck.calculation).to eq(
        "2026-01-15 <= 2026-08-16 <= 2026-07-15 => false"
      )
    end

    it "fails when current and prior current invoices both have any primary space heating upgrade type" do
      enable_common_code_rule("prior_same_upgrade_type_rebate_payment_found")

      participant = create(:user)
      contractor = Contractor.create!(business_name: "Test Contractor")
      prior_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          status: "genai_complete"
        )
      add_upgrade_type(prior_version, "dual_fuel_ducted_heat_pump")
      current_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          status: "genai_in_progress"
        )
      add_upgrade_type(current_version, "air_source_heat_pump_electric")

      result = described_class.call(invoice_version_id: current_version.id)

      expect(result[:ok]).to be(true)
      rulecheck =
        Claims::InvoiceVersionRulecheck.find_by!(
          invoice_version_id: current_version.id,
          rule_key: "prior_same_upgrade_type_rebate_payment_found"
        )
      expect(rulecheck.rule_result).to eq("fail")
      expect(rulecheck.calculation).to include(
        "current_has_space_heating=true",
        "prior_has_space_heating=true",
        "failed_checks=primary_space_heating",
        "result=fail"
      )
    end

    it "fails when current and prior current invoices both have electrical service upgrades" do
      enable_common_code_rule("prior_same_upgrade_type_rebate_payment_found")

      participant = create(:user)
      contractor = Contractor.create!(business_name: "Test Contractor")
      prior_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          status: "genai_complete"
        )
      add_upgrade_type(prior_version, "electrical_service_upgrade")
      current_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          status: "genai_in_progress"
        )
      add_upgrade_type(current_version, "electrical_service_upgrade")

      result = described_class.call(invoice_version_id: current_version.id)

      expect(result[:ok]).to be(true)
      rulecheck =
        Claims::InvoiceVersionRulecheck.find_by!(
          invoice_version_id: current_version.id,
          rule_key: "prior_same_upgrade_type_rebate_payment_found"
        )
      expect(rulecheck.rule_result).to eq("fail")
      expect(rulecheck.calculation).to include(
        "current_has_electrical_service_upgrade=true",
        "prior_has_electrical_service_upgrade=true",
        "failed_checks=electrical_service_upgrade",
        "result=fail"
      )
    end

    it "fails when the current invoice contains multiple primary space heating upgrade types" do
      enable_common_code_rule(
        "current_invoice_cannot_contain_multiple_space_systems"
      )

      participant = create(:user)
      contractor = Contractor.create!(business_name: "Test Contractor")
      current_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          status: "genai_in_progress"
        )
      add_upgrade_type(current_version, "air_source_heat_pump_electric")
      add_upgrade_type(current_version, "dual_fuel_ducted_heat_pump")

      result = described_class.call(invoice_version_id: current_version.id)

      expect(result[:ok]).to be(true)
      rulecheck =
        Claims::InvoiceVersionRulecheck.find_by!(
          invoice_version_id: current_version.id,
          rule_key: "current_invoice_cannot_contain_multiple_space_systems"
        )
      expect(rulecheck.rule_result).to eq("fail")
      expect(rulecheck.calculation).to eq(
        "current_space_heating_upgrade_type_count=2; 2 <= 1 => false"
      )
    end

    it "passes when the current invoice contains only one primary space heating upgrade type" do
      enable_common_code_rule(
        "current_invoice_cannot_contain_multiple_space_systems"
      )

      participant = create(:user)
      contractor = Contractor.create!(business_name: "Test Contractor")
      current_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          status: "genai_in_progress"
        )
      add_upgrade_type(current_version, "air_source_heat_pump_electric")
      add_upgrade_type(current_version, "heat_pump_water_heater")

      result = described_class.call(invoice_version_id: current_version.id)

      expect(result[:ok]).to be(true)
      rulecheck =
        Claims::InvoiceVersionRulecheck.find_by!(
          invoice_version_id: current_version.id,
          rule_key: "current_invoice_cannot_contain_multiple_space_systems"
        )
      expect(rulecheck.rule_result).to eq("pass")
      expect(rulecheck.calculation).to eq(
        "current_space_heating_upgrade_type_count=1; 1 <= 1 => true"
      )
    end

    it "ignores older non-current prior invoice versions for the participant" do
      enable_common_code_rule("prior_same_upgrade_type_rebate_payment_found")

      participant = create(:user)
      contractor = Contractor.create!(business_name: "Test Contractor")
      prior_invoice =
        Claims::Invoice.create!(
          session_id:
            Claims::Session.create!(created_at: now, updated_at: now).id,
          contractor_id: contractor.id,
          status: "genai_complete",
          created_at: now,
          updated_at: now
        )
      old_prior_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          invoice: prior_invoice,
          version_number: 1
        )
      add_upgrade_type(old_prior_version, "dual_fuel_ducted_heat_pump")
      current_prior_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          invoice: prior_invoice,
          version_number: 2
        )
      add_upgrade_type(current_prior_version, "windows_doors")
      current_version =
        create_invoice_version(
          participant: participant,
          contractor: contractor,
          status: "genai_in_progress"
        )
      add_upgrade_type(current_version, "air_source_heat_pump_electric")

      result = described_class.call(invoice_version_id: current_version.id)

      expect(result[:ok]).to be(true)
      rulecheck =
        Claims::InvoiceVersionRulecheck.find_by!(
          invoice_version_id: current_version.id,
          rule_key: "prior_same_upgrade_type_rebate_payment_found"
        )
      expect(rulecheck.rule_result).to eq("pass")
      expect(rulecheck.calculation).to include(
        "current_has_space_heating=true",
        "prior_has_space_heating=false",
        "result=pass"
      )
    end
  end
end
