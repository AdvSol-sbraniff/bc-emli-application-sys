# frozen_string_literal: true

module Claims
  module RevisionIssues
    class EnsureManagedIssues
      class WrongInvoiceStatus < StandardError
      end

      class StaleInvoiceVersion < StandardError
      end

      Result =
        Struct.new(
          :invoice,
          :invoice_version,
          :required_rulecheck_ids,
          :created_issue_ids,
          keyword_init: true
        )

      def self.call(**args)
        new(**args).call
      end

      def initialize(invoice:, invoice_version:)
        @invoice = invoice
        @invoice_version = invoice_version
      end

      def call
        result = nil
        ::Claims::Invoice.transaction do
          invoice = ::Claims::Invoice.lock.find(@invoice.id)
          unless invoice.status == "admin_review_inbox"
            raise WrongInvoiceStatus,
                  "Required rule issues are created only after the package is handed to the admin inbox"
          end

          version = invoice.invoice_versions.find_by!(id: @invoice_version.id)
          current_version =
            invoice
              .invoice_versions
              .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
              .first!
          unless current_version.id == version.id
            raise StaleInvoiceVersion,
                  "Required rule issues must be based on the current package version"
          end

          required = unique_managed_rulechecks(version)
          existing_identities =
            invoice
              .revision_issues
              .includes(
                :opened_from_invoice_version_rulecheck,
                :opened_from_invoice_version_located_field,
                opened_from_supporting_document_located_field: {
                  supporting_document: :supporting_document_type
                }
              )
              .to_set { |issue| SourceIdentity.for_issue(issue) }
          missing =
            required.reject do |rulecheck|
              existing_identities.include?(
                SourceIdentity.for_source(issue_type: "rule", source: rulecheck)
              )
            end

          created_issue_ids =
            missing.map do |rulecheck|
              CreateIssue.call(
                invoice: invoice,
                attributes: {
                  issue_type: "rule",
                  invoice_version_rulecheck_id: rulecheck.id
                }
              ).id
            end

          result =
            Result.new(
              invoice: invoice,
              invoice_version: version,
              required_rulecheck_ids: required.map(&:id),
              created_issue_ids: created_issue_ids
            )
        end
        result
      end

      private

      def unique_managed_rulechecks(version)
        seen = Set.new
        version
          .rulechecks
          .admin_workflow_managed
          .order(:created_at, :id)
          .select do |rulecheck|
            seen.add?(
              SourceIdentity.for_source(issue_type: "rule", source: rulecheck)
            )
          end
      end
    end
  end
end
