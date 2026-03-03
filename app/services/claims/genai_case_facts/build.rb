# frozen_string_literal: true

# app/services/claims/genai_case_facts/build.rb
#
# PURPOSE
# 1) Build "ESP database values" (case facts) for the GenAI context window.
# 2) Persist those DB-derived facts into claims.invoice_version_located_fields
#    as source_engine='code' snapshot rows (for the Confirm Your Details screen).
#
# NOTES
# - Eligibility code is NOT a DI first-class field; it lives in the deep OCR text / raw JSON.
# - Participant address: intentionally blank for now (until a proper column exists).
#
module Claims
  module GenaiCaseFacts
    class Build
      # ------------------------------------------------------------
      # PUBLIC: build_case_facts
      # ------------------------------------------------------------
      # Returns a Ruby Hash you can JSON.generate into the context window.
      #
      # Required inputs:
      # - sess: Claims::Session (has contractor_id, submitted_at)
      # - invoice_version: Claims::InvoiceVersion (has di_raw_json, first-class fields, etc.)
      #
      def self.call(sess:, invoice_version:)
        contractor = ::Contractor.find(sess.contractor_id)

        # 1) Extract eligibility_code from DI raw JSON (deep/raw OCR blob)
        eligibility_code = extract_eligibility_code(invoice_version.di_raw_json)

        # 2) Lookup eligibility record (child of users)
        elig = nil
        participant = nil

        if eligibility_code.present?
          elig = Claims::UsersEligibilitycode.find_by(eligibility_code: eligibility_code)
          participant = ::User.find(elig.user_id) if elig
        end

        # 3) Build facts blob (keep it small + deterministic)
        {
          esp_database_values: {
            sessions: {
              submitted_at: sess.submitted_at
            },

 contractors: {
  business_name: contractor.business_name,
  address: [
    contractor.street_address,
    contractor.city,
    contractor.postal_code
  ].compact.reject(&:blank?).join(", ")
},

            users_eligibilitycodes: {
              eligibility_code: eligibility_code,
              approved_at: elig&.approved_at,
              expires_at: elig&.expires_at
            },

            users: {
              participant_name: participant_name_from_user(participant),
              participant_address: nil # TODO: add once column exists on public.users
            }
          }
        }
      end

      # ------------------------------------------------------------
      # PUBLIC: persist_code_located_fields!
      # ------------------------------------------------------------
      # Writes "code engine" snapshot facts into invoice_version_located_fields.
      #
      # - source_engine='code'
      # - line_number=0
      # - confidence=100 (DB facts)
      #
      def self.persist_code_located_fields!(invoice_version_id:, case_facts:)
        now = Time.current

        facts = case_facts.fetch(:esp_database_values)

        rows = []

        # Helper for inserting typed rows
        add_row = lambda do |field_key:, value_type:, value_text: nil, normalized_value: nil|
          rows << {
            invoice_version_id: invoice_version_id,
            source_engine: "code",
            field_key: field_key,
            line_number: 0,
            value_type: value_type,
            value_text: value_text,
            value_json: nil,
            normalized_value: normalized_value,
            confidence: 100,
            page: nil,
            polygon: nil,
            evidence_text: "ESP database",
            evidence_hint: nil,
            notes: nil,
            created_at: now,
            updated_at: now
          }
        end

        # sessions.submitted_at
        submitted_at = facts.dig(:sessions, :submitted_at)
        add_row.call(
          field_key: "sessions.submitted_at",
          value_type: "date",
          value_text: submitted_at&.to_date&.iso8601,
          normalized_value: submitted_at&.to_date&.iso8601
        )

        # contractor facts
        add_row.call(
          field_key: "contractors.business_name",
          value_type: "text",
          value_text: facts.dig(:contractors, :business_name)&.to_s,
          normalized_value: facts.dig(:contractors, :business_name)&.to_s
        )

        add_row.call(
          field_key: "contractors.address",
          value_type: "text",
          value_text: facts.dig(:contractors, :address)&.to_s,
          normalized_value: facts.dig(:contractors, :address)&.to_s
        )

        # eligibility facts
        add_row.call(
          field_key: "users_eligibilitycodes.eligibility_code",
          value_type: "text",
          value_text: facts.dig(:users_eligibilitycodes, :eligibility_code)&.to_s,
          normalized_value: facts.dig(:users_eligibilitycodes, :eligibility_code)&.to_s
        )

        approved_at = facts.dig(:users_eligibilitycodes, :approved_at)
        add_row.call(
          field_key: "users_eligibilitycodes.approved_at",
          value_type: "date",
          value_text: approved_at&.to_date&.iso8601,
          normalized_value: approved_at&.to_date&.iso8601
        )

        expires_at = facts.dig(:users_eligibilitycodes, :expires_at)
        add_row.call(
          field_key: "users_eligibilitycodes.expires_at",
          value_type: "date",
          value_text: expires_at&.to_date&.iso8601,
          normalized_value: expires_at&.to_date&.iso8601
        )

        # participant facts
        add_row.call(
          field_key: "users.participant_name",
          value_type: "text",
          value_text: facts.dig(:users, :participant_name)&.to_s,
          normalized_value: facts.dig(:users, :participant_name)&.to_s
        )

        # participant_address intentionally omitted (nil) until you have the column.
        # You can still snapshot a nil row if you want, but it adds noise.

        # Upsert so reruns don't explode unique constraint:
        # UNIQUE (invoice_version_id, source_engine, field_key, line_number)
        #
        # NOTE: the index/constraint name in your DDL is:
        #   invoice_version_located_fields_uniq
        #
        Claims::InvoiceVersionLocatedField.upsert_all(
          rows,
          unique_by: :invoice_version_located_fields_uniq
        )
      end

      # ============================================================
      # INTERNAL HELPERS
      # ============================================================

      # Pull eligibility code from the deep/raw OCR blob.
      # Examples: ESP1-136a31ba (yours), could also be ESP2/ESP3.
def self.extract_eligibility_code(di_raw_json)
  return nil if di_raw_json.blank?

  s = di_raw_json.to_json

  # Accept OCR confusion: 1 <-> I, allow whitespace + different dash chars
  m = s.match(/\bESP(?:[123]|I)\s*[-–—]\s*([0-9a-fA-F]{8})\b/)
  return "ESP1-#{m[1]}" if m && m[0].match?(/\bESPI\b/)   # normalize ESPI -> ESP1
  return "ESP#{m[0][3]}-#{m[1]}" if m                    # ESP1/2/3

  # Fallback: longer IDs (still allow I)
  m2 = s.match(/\bESP(?:[123]|I)\s*[-–—]\s*([A-Za-z0-9]{6,})\b/)
  return nil unless m2

  prefix = m2[0][0,4] # "ESP1" / "ESP2" / "ESP3" / "ESPI"
  prefix = "ESP1" if prefix == "ESPI"
  "#{prefix}-#{m2[1]}"
end
      def self.participant_name_from_user(user)
        return nil if user.nil?

        # If later you add participant_name column, swap to that.
        # For now use first+last when present, else email as last resort.
        fn = user.first_name.to_s.strip
        ln = user.last_name.to_s.strip
        name = [fn, ln].reject(&:empty?).join(" ").strip
        return name if name.present?

        user.email.to_s.presence
      end
    end
  end
end