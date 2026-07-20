# frozen_string_literal: true

module Claims
  module RevisionIssues
    class CreateIssue
      class ClosedIssueExists < StandardError
      end

      class AlreadyInRound < StandardError
      end

      class SourceMismatch < StandardError
      end

      SOURCE_KEYS = %i[
        invoice_version_rulecheck_id
        invoice_version_located_field_id
        supporting_document_located_field_id
        di_field_key
      ].freeze

      def self.call(**args)
        new(**args).call
      end

      def initialize(invoice:, attributes:)
        @invoice = invoice
        @attributes = attributes.to_h.symbolize_keys
      end

      def call
        issue = nil
        ::Claims::Invoice.transaction do
          invoice = ::Claims::Invoice.lock.find(@invoice.id)
          round = EnsureDraftRound.call(invoice: invoice)

          issue_type = @attributes.fetch(:issue_type).to_s
          source = load_source!(issue_type)
          validate_source_version!(source, issue_type, round)
          identity =
            SourceIdentity.for_source(issue_type: issue_type, source: source)
          issue = find_logical_issue(invoice, identity)
          if issue&.closed?
            raise ClosedIssueExists, "This problem was already closed"
          end

          issue ||=
            invoice.revision_issues.create!(
              issue_attributes(issue_type, source, round)
            )
          if issue
               .comments
               .where(revision_round_id: round.id, author_type: "admin")
               .exists?
            raise AlreadyInRound,
                  "This issue already has an admin recommendation draft"
          end

          issue.comments.create!(
            revision_round: round,
            author_type: "admin",
            admin_recommended_remedy: nil,
            comment_text: BuildAdminCommentDraft.call(issue: issue)
          )
        end
        issue
      end

      private

      def load_source!(issue_type)
        case issue_type
        when "rule"
          ::Claims::InvoiceVersionRulecheck.find(
            @attributes.fetch(:invoice_version_rulecheck_id)
          )
        when "invoice_field"
          ::Claims::InvoiceVersionLocatedField.find(
            @attributes.fetch(:invoice_version_located_field_id)
          )
        when "supporting_document_field"
          ::Claims::SupportingDocumentLocatedField.find(
            @attributes.fetch(:supporting_document_located_field_id)
          )
        when "di_field"
          @attributes.fetch(:di_field_key).to_s
        else
          raise ActiveRecord::RecordNotFound, "Unsupported issue type"
        end
      end

      def source_version_id(source, issue_type, round)
        case issue_type
        when "rule", "invoice_field"
          source.invoice_version_id
        when "supporting_document_field"
          source.supporting_document.invoice_version_id
        when "di_field"
          round.invoice_version_id
        end
      end

      def validate_source_version!(source, issue_type, round)
        if source_version_id(source, issue_type, round) ==
             round.invoice_version_id
          return
        end

        raise SourceMismatch,
              "Source must belong to the round's invoice version"
      end

      def issue_attributes(issue_type, source, round)
        attrs = { issue_type: issue_type, status: "open" }
        case issue_type
        when "rule"
          attrs[:opened_from_invoice_version_rulecheck_id] = source.id
        when "invoice_field"
          attrs[:opened_from_invoice_version_located_field_id] = source.id
        when "supporting_document_field"
          attrs[:opened_from_supporting_document_located_field_id] = source.id
        when "di_field"
          attrs[:opened_from_di_invoice_version_id] = round.invoice_version_id
          attrs[:opened_from_di_field_key] = source
        end
        attrs
      end

      def find_logical_issue(invoice, identity)
        invoice
          .revision_issues
          .includes(
            :opened_from_invoice_version_rulecheck,
            :opened_from_invoice_version_located_field,
            :opened_from_supporting_document_located_field
          )
          .detect do |candidate|
            SourceIdentity.for_issue(candidate) == identity
          end
      end
    end
  end
end
