# frozen_string_literal: true

module Claims
  class RevisionIssue < ApplicationRecord
    self.table_name = "claims.revision_issues"

    ISSUE_TYPES = %w[
      rule
      invoice_field
      supporting_document_field
      di_field
    ].freeze

    STATUSES = %w[
      open
      closed_via_corrected_documentation
      closed_via_attestation
      closed_via_exception
      closed_as_withdrawn
    ].freeze

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id,
               inverse_of: :revision_issues

    belongs_to :opened_from_invoice_version_rulecheck,
               class_name: "Claims::InvoiceVersionRulecheck",
               foreign_key: :opened_from_invoice_version_rulecheck_id,
               optional: true

    belongs_to :opened_from_invoice_version_located_field,
               class_name: "Claims::InvoiceVersionLocatedField",
               foreign_key: :opened_from_invoice_version_located_field_id,
               optional: true

    belongs_to :opened_from_supporting_document_located_field,
               class_name: "Claims::SupportingDocumentLocatedField",
               foreign_key: :opened_from_supporting_document_located_field_id,
               optional: true

    belongs_to :opened_from_di_invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :opened_from_di_invoice_version_id,
               optional: true

    has_many :comments,
             -> { order(created_at: :asc, id: :asc) },
             class_name: "Claims::RevisionIssueComment",
             foreign_key: :revision_issue_id,
             inverse_of: :revision_issue,
             dependent: :destroy

    has_many :revision_rounds, through: :comments

    scope :open_issues, -> { where(status: "open") }
    scope :closed_issues, -> { where.not(status: "open") }

    validates :issue_type, inclusion: { in: ISSUE_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validate :one_matching_source
    validate :source_belongs_to_invoice
    validate :closed_issue_is_immutable, on: :update

    def open?
      status == "open"
    end

    def closed?
      !open?
    end

    def field_issue?
      issue_type.in?(%w[invoice_field supporting_document_field di_field])
    end

    def contractor_visible?
      comments
        .joins(:revision_round)
        .where.not("claims.revision_rounds.admin_sent_at" => nil)
        .exists?
    end

    def source_reference
      {
        invoice_version_rulecheck_id: opened_from_invoice_version_rulecheck_id,
        invoice_version_located_field_id:
          opened_from_invoice_version_located_field_id,
        supporting_document_located_field_id:
          opened_from_supporting_document_located_field_id,
        di_field_key: opened_from_di_field_key
      }.compact
    end

    private

    def one_matching_source
      present_sources = [
        opened_from_invoice_version_rulecheck_id,
        opened_from_invoice_version_located_field_id,
        opened_from_supporting_document_located_field_id,
        opened_from_di_field_key.presence
      ].compact
      unless present_sources.one?
        errors.add(:base, "must reference exactly one source")
      end

      expected =
        case issue_type
        when "rule"
          opened_from_invoice_version_rulecheck_id.present?
        when "invoice_field"
          opened_from_invoice_version_located_field_id.present?
        when "supporting_document_field"
          opened_from_supporting_document_located_field_id.present?
        when "di_field"
          opened_from_di_field_key.present? &&
            opened_from_di_invoice_version_id.present?
        else
          false
        end
      errors.add(:issue_type, "does not match its source") unless expected
    end

    def source_belongs_to_invoice
      return if invoice_id.blank?

      source_invoice_id =
        case issue_type
        when "rule"
          invoice_id_for_version(
            opened_from_invoice_version_rulecheck&.invoice_version_id
          )
        when "invoice_field"
          invoice_id_for_version(
            opened_from_invoice_version_located_field&.invoice_version_id
          )
        when "supporting_document_field"
          invoice_id_for_version(
            opened_from_supporting_document_located_field&.supporting_document&.invoice_version_id
          )
        when "di_field"
          invoice_id_for_version(opened_from_di_invoice_version_id)
        end
      return if source_invoice_id == invoice_id

      errors.add(:base, "source must belong to the invoice")
    end

    def invoice_id_for_version(version_id)
      return if version_id.blank?

      ::Claims::InvoiceVersion.where(id: version_id).pick(:invoice_id)
    end

    def closed_issue_is_immutable
      return unless status_was.present? && status_was != "open"
      return unless changes.except("updated_at").any?

      errors.add(:base, "closed issues are immutable")
    end
  end
end
