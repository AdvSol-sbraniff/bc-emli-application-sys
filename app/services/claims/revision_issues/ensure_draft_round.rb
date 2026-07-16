# frozen_string_literal: true

module Claims
  module RevisionIssues
    class EnsureDraftRound
      class RoundAlreadyActive < StandardError
      end

      class WrongInvoiceStatus < StandardError
      end

      def self.call(invoice:)
        invoice = ::Claims::Invoice.lock.find(invoice.id)
        unless invoice.status == "admin_review_inbox"
          raise WrongInvoiceStatus,
                "Revision issues can only be prepared in the first-level admin inbox"
        end

        latest = invoice.revision_rounds.newest_first.first
        return latest if latest&.draft?

        if latest&.waiting_for_contractor?
          raise RoundAlreadyActive,
                "The open revision issues are still with the contractor"
        end

        version =
          invoice
            .invoice_versions
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .first!
        invoice.revision_rounds.create!(
          invoice_version: version,
          round_number: latest&.round_number.to_i + 1
        )
      rescue ActiveRecord::RecordNotUnique
        invoice.revision_rounds.newest_first.first!
      end
    end
  end
end
