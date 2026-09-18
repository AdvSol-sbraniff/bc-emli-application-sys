# frozen_string_literal: true

require "digest"
require "timeout"

module Claims
  module RuleAudits
    class Audit
      class InvalidResponse < StandardError
      end

      OUTPUT_FIELDS = %w[
        advice
        proposed_rule_prompt
        proposed_precheck_action
        proposed_contractor_guidance
      ].freeze

      def initialize(
        source_engine:,
        rule_key:,
        invoice_id:,
        selected_invoice_version_id: nil
      )
        @source_engine = source_engine.to_s
        @rule_key = rule_key.to_s
        @invoice_id = invoice_id.to_s
        @selected_invoice_version_id = selected_invoice_version_id.presence
      end

      def call
        guidance = Guidance.for_engine(@source_engine)
        context =
          ContextBuilder.new(
            source_engine: @source_engine,
            rule_key: @rule_key,
            invoice_id: @invoice_id,
            selected_invoice_version_id: @selected_invoice_version_id,
            guidance: guidance
          ).call
        system_record = Configuration.system_record
        deployment =
          ::Claims::Genai::DeploymentConfig.current[:comparison_deployment_name]
        if deployment.blank?
          raise Configuration::Unavailable,
                "Configure the comparison and rule audit model in System Config first."
        end

        messages =
          [
            {
              role: "system",
              content: [{ type: "input_text", text: system_record }]
            }
          ] + context.fetch(:contextwindowjson)
        if JSON.generate(messages).bytesize > ContextBuilder::MAX_CONTEXT_BYTES
          raise ContextBuilder::TooLarge,
                "The complete audit context exceeds the supported size. No evidence was truncated or sent."
        end

        payload =
          ::Claims::Genai::NodeClient.rule_audit(
            contextwindowjson: messages,
            attachments: context.fetch(:attachments),
            deployment_name: deployment,
            diagnostic_context: {
              step_type: "rule_package_audit",
              invoice_id: @invoice_id,
              invoice_version_id: @selected_invoice_version_id,
              source_engine: @source_engine,
              rule_key: @rule_key
            }.compact
          )
        output = validated_output(payload)
        transport =
          validated_transport(
            payload,
            messages,
            context.fetch(:attachments),
            deployment
          )
        output.merge(
          transport: transport,
          evidence:
            context.fetch(:manifest).merge(
              file_transport_status:
                "Verified: every declared source file was supplied to the model; see transport hashes and the recorded missing-evidence limitations."
            ),
          system_record_sha256: Digest::SHA256.hexdigest(system_record),
          guidance_sha256: guidance.fetch("reference_sha256"),
          completed_at: Time.current.iso8601,
          saved: false
        )
      end

      private

      def validated_transport(payload, messages, attachments, deployment)
        transport = payload["transport"]
        files = transport.is_a?(Hash) ? transport["attachments"] : nil
        valid =
          transport.is_a?(Hash) &&
            transport["provider_status"] == "completed" &&
            transport["deployment"] == deployment &&
            transport["context_sha256"] ==
              Digest::SHA256.hexdigest(JSON.generate(messages)) &&
            transport["context_record_count"] == messages.size &&
            transport["attachment_count"] == attachments.size &&
            transport["omissions"] == [] && files.is_a?(Array) &&
            files.size == attachments.size
        if valid
          valid =
            files
              .zip(attachments)
              .all? do |file, expected|
                file.is_a?(Hash) && file["reference"] == expected[:reference] &&
                  file["storage_key"] == expected[:storageKey] &&
                  file["byte_size"].is_a?(Integer) &&
                  file["byte_size"].positive? &&
                  /\A[0-9a-f]{64}\z/i.match?(file["sha256"].to_s)
              end
        end
        unless valid
          raise InvalidResponse,
                "The AI service did not confirm the complete audit evidence. Retry the audit."
        end

        transport
      end

      def validated_output(payload)
        unless payload.is_a?(Hash) &&
                 OUTPUT_FIELDS.all? { |key| payload.key?(key) }
          raise InvalidResponse,
                "The audit model returned an incomplete response. Try again."
        end
        OUTPUT_FIELDS.each do |key|
          value = payload[key]
          next if key != "advice" && value.nil?

          unless value.is_a?(String) && value.strip.present? &&
                   value.length <= 100_000
            raise InvalidResponse,
                  "The audit model returned an invalid #{key.humanize.downcase} field. Try again."
          end
        end
        if @source_engine == "code" && payload["proposed_rule_prompt"].present?
          raise InvalidResponse,
                "The audit proposed a GenAI prompt for a code rule. Retry the audit."
        end
        payload.slice(*OUTPUT_FIELDS).symbolize_keys
      end
    end
  end
end
