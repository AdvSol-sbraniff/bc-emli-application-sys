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
          path: %i[invoices submitted_at]
        },
        "contractors.business_name" => {
          value_type: "text",
          path: %i[contractors business_name]
        },
        "contractors.address" => {
          value_type: "text",
          path: %i[contractors address]
        },
        "users_eligibilitycodes.eligibility_code" => {
          value_type: "text",
          path: %i[users_eligibilitycodes eligibility_code]
        },
        "users_eligibilitycodes.income_level" => {
          value_type: "number",
          path: %i[users_eligibilitycodes income_level]
        },
        "users_eligibilitycodes.approved_at" => {
          value_type: "date",
          path: %i[users_eligibilitycodes approved_at]
        },
        "users_eligibilitycodes.expires_at" => {
          value_type: "date",
          path: %i[users_eligibilitycodes expires_at]
        },
        "users.participant_name" => {
          value_type: "text",
          path: %i[users participant_name]
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
              elig&.income_level ||
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

      def self.case_facts_for_upgrade_type(case_facts:, invoice_upgrade_type:)
        facts = case_facts.deep_dup
        facts[
          :supporting_document_summary_for_upgrade_type
        ] = build_supporting_document_summary_for_upgrade_type(
          supporting_document_summary: facts[:supporting_document_summary],
          invoice_upgrade_type: invoice_upgrade_type
        )
        facts
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
            value_text:
              persisted_value_text_for(definition[:value_type], raw_value)
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

      def self.persist_classifier_located_fields!(
        invoice_version_id:,
        classifier_payload:
      )
        return unless classifier_payload.is_a?(Hash)

        invoice_version = Claims::InvoiceVersion.find(invoice_version_id)
        common_type =
          Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
        upgrade_types =
          classifier_detected_upgrade_types(
            classifier_payload
          ).filter_map do |key|
            Claims::InvoiceUpgradeType.find_by(upgrade_type_key: key)
          end
        upgrade_types = [common_type] if upgrade_types.empty?

        now = Time.current
        rows = []

        eligibility_code =
          classifier_payload["eligibility_code"] ||
            classifier_payload[:eligibility_code]
        add_classifier_row(
          rows,
          invoice_version_id: invoice_version.id,
          invoice_upgrade_type_id: common_type.id,
          field_key: "classifier.eligibility_code",
          value_type: "text",
          value: eligibility_code,
          confidence: 100,
          evidence_text: "Triage classifier",
          now: now
        )

        detected_upgrade_types =
          classifier_detected_upgrade_types(classifier_payload)
        add_classifier_row(
          rows,
          invoice_version_id: invoice_version.id,
          invoice_upgrade_type_id: common_type.id,
          field_key: "classifier.detected_upgrade_types",
          value_type: "json",
          value: detected_upgrade_types,
          confidence: detected_upgrade_types.any? ? 100 : 0,
          evidence_text: "Triage classifier",
          now: now
        )

        product_refs = classifier_product_references(classifier_payload)
        upgrade_types.each do |upgrade_type|
          {
            "classifier.ahri_reference" => product_refs[:ahri_reference],
            "classifier.neea_reference" => product_refs[:neea_reference],
            "classifier.awhp_reference" => product_refs[:awhp_reference],
            "classifier.ohpa_reference" => product_refs[:ohpa_reference],
            "classifier.product_model_number" =>
              product_refs[:product_model_number],
            "classifier.product_manufacturer" =>
              product_refs[:product_manufacturer]
          }.each do |field_key, value|
            add_classifier_row(
              rows,
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              field_key: field_key,
              value_type: "text",
              value: value,
              confidence: value.to_s.strip.present? ? 90 : 0,
              evidence_text: "Triage classifier",
              now: now
            )
          end
        end

        Claims::InvoiceVersionLocatedField.transaction do
          Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: invoice_version.id,
            source_engine: "classifier"
          ).delete_all

          Claims::InvoiceVersionLocatedField.insert_all!(rows) if rows.any?
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
          ::Claims::CodeLocatedField
            .where(enabled: true)
            .pluck(:code_field_key)
            .map(&:to_s)
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
            .includes(
              :supporting_document_type,
              :supporting_document_visual_findings,
              supporting_document_located_fields:
                :supporting_document_type_located_field
            )
            .order(created_at: :asc, id: :asc)
            .map do |doc|
              {
                supporting_document_id: doc.id,
                type_key: doc.supporting_document_type&.type_key,
                type_description: doc.supporting_document_type&.description,
                original_filename: doc.original_filename,
                classification_status: doc.classification_status,
                classification_confidence: doc.classification_confidence,
                supplement_routing_quality: doc.supplement_routing_quality,
                supplement_routing_quality_reason:
                  doc.supplement_routing_quality_reason,
                located_fields:
                  serialize_supporting_document_located_fields(doc),
                visual_findings:
                  serialize_supporting_document_visual_findings(doc)
              }
            end

        type_counts = count_document_types(docs)

        {
          document_count: docs.size,
          typed_document_count:
            docs.count { |row| row[:type_key].to_s.present? },
          type_keys:
            docs.map { |row| row[:type_key].to_s.presence }.compact.uniq.sort,
          type_counts: type_counts,
          documents: docs
        }
      rescue StandardError
        {
          document_count: 0,
          typed_document_count: 0,
          type_keys: [],
          type_counts: {
          },
          documents: []
        }
      end

      def self.build_supporting_document_summary_for_upgrade_type(
        supporting_document_summary:,
        invoice_upgrade_type:
      )
        summary = supporting_document_summary || {}
        documents = Array(summary[:documents] || summary["documents"])
        configured_types =
          enabled_supporting_document_types_for_upgrade_type(
            invoice_upgrade_type: invoice_upgrade_type
          )
        configured_type_keys = configured_types.map(&:type_key).compact.sort

        relevant_documents =
          documents.select do |row|
            configured_type_keys.include?(
              row[:type_key].to_s.presence || row["type_key"].to_s.presence
            )
          end

        present_type_keys =
          relevant_documents
            .map do |row|
              row[:type_key].to_s.presence || row["type_key"].to_s.presence
            end
            .compact
            .uniq
            .sort

        {
          upgrade_type_key: invoice_upgrade_type.upgrade_type_key,
          upgrade_type_description: invoice_upgrade_type.description,
          configured_type_keys: configured_type_keys,
          configured_types:
            configured_types.map do |type|
              { type_key: type.type_key, type_description: type.description }
            end,
          configured_document_count: relevant_documents.size,
          present_configured_type_keys: present_type_keys,
          missing_configured_type_keys:
            configured_type_keys - present_type_keys,
          present_configured_type_counts:
            count_document_types(relevant_documents),
          configured_documents: relevant_documents
        }
      rescue StandardError
        {
          upgrade_type_key: invoice_upgrade_type&.upgrade_type_key,
          upgrade_type_description: invoice_upgrade_type&.description,
          configured_type_keys: [],
          configured_types: [],
          configured_document_count: 0,
          present_configured_type_keys: [],
          missing_configured_type_keys: [],
          present_configured_type_counts: {
          },
          configured_documents: []
        }
      end

      def self.enabled_supporting_document_types_for_upgrade_type(
        invoice_upgrade_type:
      )
        invoice_upgrade_type
          .supporting_document_types
          .where(enabled: true)
          .order(:type_key, :id)
      rescue StandardError
        []
      end

      def self.count_document_types(documents)
        Array(documents)
          .each_with_object(Hash.new(0)) do |row, counts|
            type_key =
              row[:type_key].to_s.presence || row["type_key"].to_s.presence
            next if type_key.blank?

            counts[type_key] += 1
          end
          .sort
          .to_h
      end

      def self.serialize_supporting_document_located_fields(document)
        document
          .supporting_document_located_fields
          .sort_by do |field|
            [
              field.supporting_document_type_located_field&.field_number ||
                99_999,
              field.field_key.to_s
            ]
          end
          .map do |field|
            {
              supporting_document_located_field_id: field.id,
              supporting_document_type_located_field_id:
                field.supporting_document_type_located_field_id,
              field_key: field.field_key,
              source_engine: field.source_engine,
              value_type: field.value_type,
              value_text: field.value_text,
              value_json: field.value_json,
              confidence: field.confidence,
              page: field.page,
              polygon: field.polygon,
              evidence_text: field.evidence_text
            }
          end
      end

      def self.serialize_supporting_document_visual_findings(document)
        document
          .supporting_document_visual_findings
          .sort_by { |finding| [finding.finding_seqno || 99_999, finding.id] }
          .map do |finding|
            {
              supporting_document_visual_finding_id: finding.id,
              finding_seqno: finding.finding_seqno,
              source_engine: finding.source_engine,
              finding_type: finding.finding_type,
              page: finding.page,
              summary: finding.summary,
              legibility: finding.legibility,
              relevant_text_seen: finding.relevant_text_seen,
              confidence: finding.confidence
            }
          end
      end

      def self.add_classifier_row(
        rows,
        invoice_version_id:,
        invoice_upgrade_type_id:,
        field_key:,
        value_type:,
        value:,
        confidence:,
        evidence_text:,
        now:
      )
        value_present =
          value_type == "json" ? !value.nil? : value.to_s.strip.present?

        rows << {
          invoice_version_id: invoice_version_id,
          invoice_upgrade_type_id: invoice_upgrade_type_id,
          source_engine: "classifier",
          field_key: field_key,
          value_type: value_type,
          value_text:
            (value_present && value_type != "json" ? value.to_s.strip : nil),
          value_json: value_type == "json" ? value : nil,
          confidence: confidence,
          page: nil,
          polygon: nil,
          evidence_text: evidence_text,
          created_at: now,
          updated_at: now
        }
      end

      def self.classifier_detected_upgrade_types(classifier_payload)
        rows =
          classifier_payload["detected_upgrade_types"] ||
            classifier_payload[:detected_upgrade_types]

        Array(rows)
          .filter_map do |row|
            next unless row.is_a?(Hash)

            row["upgrade_type_key"] || row[:upgrade_type_key]
          end
          .map { |key| key.to_s.strip }
          .reject { |key| key.empty? || key == "common" }
          .uniq
      end

      def self.classifier_product_references(classifier_payload)
        refs =
          classifier_payload["product_references"] ||
            classifier_payload[:product_references]
        refs = {} unless refs.is_a?(Hash)

        {
          ahri_reference: refs["ahri_reference"] || refs[:ahri_reference],
          neea_reference: refs["neea_reference"] || refs[:neea_reference],
          awhp_reference: refs["awhp_reference"] || refs[:awhp_reference],
          ohpa_reference: refs["ohpa_reference"] || refs[:ohpa_reference],
          product_model_number:
            refs["product_model_number"] || refs[:product_model_number] ||
              refs["model_number"] || refs[:model_number],
          product_manufacturer:
            refs["product_manufacturer"] || refs[:product_manufacturer] ||
              refs["manufacturer"] || refs[:manufacturer]
        }.transform_values { |value| value.to_s.strip.presence }
      end
    end
  end
end
