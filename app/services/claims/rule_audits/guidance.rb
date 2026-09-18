# frozen_string_literal: true

require "digest"
require "json"

module Claims
  module RuleAudits
    class Guidance
      class Unavailable < StandardError
      end

      def self.for_engine(source_engine)
        unless %w[genai code].include?(source_engine.to_s)
          raise ContextBuilder::InvalidInput,
                "Choose a GenAI or code rule to audit."
        end
        reference_path =
          Rails.root.join("config/claims/rule_improvement_guidance.json")
        content = reference_path.read.gsub("\r\n", "\n")
        reference = JSON.parse(content)
        reference
          .fetch("sources")
          .each do |relative_path, expected_digest|
            source = Rails.root.join(relative_path).cleanpath
            unless source.to_s.start_with?("#{Rails.root}/") && source.file? &&
                     Digest::SHA256.hexdigest(source.read.gsub("\r\n", "\n")) ==
                       expected_digest
              raise Unavailable,
                    "The shared rule improvement guidance needs updating. Run npm run rule-audit:guidance before auditing."
            end
          end
        reference
          .fetch("engines")
          .fetch(source_engine.to_s)
          .merge(
            "reference_sha256" => Digest::SHA256.hexdigest(content),
            "purpose" =>
              "Human workflow and investigation reference exported from the same React guidance. It contains no measured signal values for this invoice or rule."
          )
      rescue Errno::ENOENT, JSON::ParserError, KeyError
        raise Unavailable,
              "The shared rule improvement guidance is unavailable. Run npm run rule-audit:guidance."
      end
    end
  end
end
