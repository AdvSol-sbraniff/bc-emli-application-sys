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
      CODE_FIELD_DEFINITIONS = {
        "invoices.submitted_at" => {
          value_type: "date",
          path: [:invoices, :submitted_at]
        },
        "contractors.business_name" => {
          value_type: "text",
          path: [:contractors, :business_name]
        },
        "contractors.address" => {
          value_type: "text",
          path: [:contractors, :address]
        },
        "users_eligibilitycodes.eligibility_code" => {
          value_type: "text",
          path: [:users_eligibilitycodes, :eligibility_code]
        },
        "users_eligibilitycodes.income_level" => {
          value_type: "number",
          path: [:users_eligibilitycodes, :income_level]
        },
        "users_eligibilitycodes.approved_at" => {
          value_type: "date",
          path: [:users_eligibilitycodes, :approved_at]
        },
        "users_eligibilitycodes.expires_at" => {
          value_type: "date",
          path: [:users_eligibilitycodes, :expires_at]
        },
        "users.participant_name" => {
          value_type: "text",
          path: [:users, :participant_name]
        }
      }.freeze

      # ------------------------------------------------------------
      # PUBLIC: build_case_facts
      # ------------------------------------------------------------
      # Returns a Ruby Hash you can JSON.generate into the context window.
      #
      # Required inputs:
      # - sess: Claims::Session grouping row
      # - invoice: Claims::Invoice (owns contractor_id, submitter_id, submitted_at)
      # - eligibility_code: code located by the classifier call from OCR text
      #
      def self.call(sess:, invoice: nil, eligibility_code: nil)
        build_shared_context(
          sess: sess,
          invoice: invoice,
          eligibility_code: eligibility_code
        ).fetch(:case_facts)
      end

      # Builds DB facts for downstream common/upgrade GenAI calls after the
      # OCR-only classifier has located the eligibility code.
      def self.build_shared_context(sess:, invoice: nil, eligibility_code: nil)
        invoice ||=
          Claims::Invoice
            .where(session_id: sess.id)
            .order(:created_at, :id)
            .first
        if invoice.nil?
          raise ArgumentError, "Missing invoice for session_id=#{sess.id}"
        end

        contractor = ::Contractor.find(invoice.contractor_id)

        elig = nil
        participant = nil
        eligibility_code = normalize_eligibility_code(eligibility_code)

        if eligibility_code.present?
          elig = find_eligibility_code(eligibility_code)
          participant = ::User.find(elig.user_id) if elig
        end

        # 3) Build facts blob (keep it small + deterministic)
        esp_database_values = {
          invoices: {
            submitted_at: invoice.submitted_at
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
            eligibility_code: elig&.eligibility_code,
            income_level:
              income_level_from_eligibility_code(elig&.eligibility_code),
            approved_at: elig&.approved_at,
            expires_at: elig&.expires_at
          },
          users: {
            participant_name: participant_name_from_user(participant),
            participant_address: nil # TODO: add once column exists on public.users
          },
          classifier: {
            eligibility_code: eligibility_code
          }
        }

        prune_disabled_code_fields!(esp_database_values)

        case_facts = {
          esp_database_values: esp_database_values,
          supporting_document_summary:
            build_supporting_document_summary(invoice: invoice)
        }

        {
          case_facts: case_facts,
          classifier_eligibility_code: eligibility_code
        }
      end

      # ------------------------------------------------------------
      # PUBLIC: persist_code_located_fields!
      # ------------------------------------------------------------
      # Writes "code engine" snapshot facts into invoice_version_located_fields.
      #
      # - source_engine='code'
      # - confidence=100 (DB facts)
      #
      def self.persist_code_located_fields!(
        invoice_version_id:,
        case_facts:,
        classifier_eligibility_code: nil
      )
        now = Time.current

        facts = case_facts.fetch(:esp_database_values)

        rows = []

        # Helper for inserting typed rows
        add_row =
          lambda do |field_key:, value_type:, value_text: nil|
            rows << {
              invoice_version_id: invoice_version_id,
              source_engine: "code",
              field_key: field_key,
              value_type: value_type,
              value_text: value_text,
              value_json: nil,
              confidence: 100,
              page: nil,
              polygon: nil,
              evidence_text: "ESP database",
              created_at: now,
              updated_at: now
            }
          end

        enabled_code_field_keys.each do |field_key|
          definition = CODE_FIELD_DEFINITIONS[field_key]
          next unless definition

          raw_value = facts.dig(*definition[:path])

          add_row.call(
            field_key: field_key,
            value_type: definition[:value_type],
            value_text: persisted_value_text_for(definition[:value_type], raw_value)
          )
        end

        # participant_address intentionally omitted (nil) until you have the column.
        # You can still snapshot a nil row if you want, but it adds noise.
        return if rows.empty?

        Claims::InvoiceVersionLocatedField.transaction do
          Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: invoice_version_id,
            source_engine: "code"
          ).delete_all

          Claims::InvoiceVersionLocatedField.insert_all!(rows)
        end
      end

      # ============================================================
      # INTERNAL HELPERS
      # ============================================================
      def self.normalize_eligibility_code(value)
        value.to_s.strip.presence
      end

      def self.find_eligibility_code(eligibility_code)
        Claims::UsersEligibilitycode.where(
          "LOWER(eligibility_code) = LOWER(?)",
          eligibility_code.to_s.strip
        ).first
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

      def self.income_level_from_eligibility_code(eligibility_code)
        token = eligibility_code.to_s.strip.upcase
        return 1 if token.start_with?("ESP1") || token.start_with?("ESPI")
        return 2 if token.start_with?("ESP2")
        return 3 if token.start_with?("ESP3")

        nil
      end

      def self.enabled_code_field_keys
        configured_keys =
          ::Claims::CodeLocatedField.where(enabled: true).pluck(:code_field_key).map(&:to_s)
        return configured_keys if configured_keys.present?

        CODE_FIELD_DEFINITIONS.keys
      rescue StandardError
        CODE_FIELD_DEFINITIONS.keys
      end

      def self.prune_disabled_code_fields!(esp_database_values)
        disabled_keys = CODE_FIELD_DEFINITIONS.keys - enabled_code_field_keys

        disabled_keys.each do |field_key|
          path = CODE_FIELD_DEFINITIONS.dig(field_key, :path)
          next if path.blank?

          delete_nested_value!(esp_database_values, path.dup)
        end
      end

      def self.delete_nested_value!(hash, path)
        key = path.shift
        return if key.nil? || hash.blank?

        if path.empty?
          hash.delete(key)
          return
        end

        child = hash[key]
        return unless child.is_a?(Hash)

        delete_nested_value!(child, path)
      end

      def self.persisted_value_text_for(value_type, raw_value)
        case value_type
        when "date"
          raw_value&.to_date&.iso8601
        else
          raw_value&.to_s
        end
      end

      def self.build_supporting_document_summary(invoice:)
        docs =
          invoice
            .supporting_documents
            .includes(:supporting_document_type)
            .order(created_at: :asc, id: :asc)
            .map do |doc|
              {
                supporting_document_id: doc.id,
                type_key: doc.supporting_document_type&.type_key,
                type_description: doc.supporting_document_type&.description,
                original_filename: doc.original_filename,
                classification_status: doc.classification_status,
                classification_confidence: doc.classification_confidence
              }
            end

        {
          document_count: docs.size,
          type_keys:
            docs.map { |row| row[:type_key].to_s.presence }.compact.uniq.sort,
          documents: docs
        }
      rescue StandardError
        {
          document_count: 0,
          type_keys: [],
          documents: []
        }
      end
    end
  end
end
