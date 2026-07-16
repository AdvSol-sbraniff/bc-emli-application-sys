# frozen_string_literal: true

module Claims
  class RevisionIssueComment < ApplicationRecord
    self.table_name = "claims.revision_issue_comments"

    AUTHOR_TYPES = %w[admin contractor].freeze
    ADMIN_REMEDIES = %w[
      correct_and_reupload_invoice
      upload_supporting_document
      provide_attestation
      provide_explanation
    ].freeze
    CONTRACTOR_METHODS = %w[
      corrected_invoice_uploaded
      supporting_document_uploaded
      attestation_provided
      explanation_provided
      unable_to_resolve
    ].freeze

    belongs_to :revision_issue,
               class_name: "Claims::RevisionIssue",
               foreign_key: :revision_issue_id,
               inverse_of: :comments

    belongs_to :revision_round,
               class_name: "Claims::RevisionRound",
               foreign_key: :revision_round_id,
               inverse_of: :comments

    validates :author_type, inclusion: { in: AUTHOR_TYPES }
    validates :admin_recommended_remedy,
              inclusion: {
                in: ADMIN_REMEDIES
              },
              allow_nil: true
    validates :contractor_response_method,
              inclusion: {
                in: CONTRACTOR_METHODS
              },
              allow_nil: true
    validates :comment_text, presence: true
    validate :role_specific_fields
    validate :asserted_value_scope
    validate :issue_and_round_share_invoice

    def admin?
      author_type == "admin"
    end

    def contractor?
      author_type == "contractor"
    end

    def contractor_response_complete?
      return false unless contractor?
      if contractor_response_method.blank? || comment_text.to_s.strip.blank?
        return false
      end
      if contractor_response_method == "attestation_provided" &&
           revision_issue.field_issue? &&
           contractor_asserted_value.to_s.strip.blank?
        return false
      end

      true
    end

    private

    def role_specific_fields
      if admin?
        if contractor_response_method.present? ||
             contractor_asserted_value.present?
          errors.add(
            :base,
            "admin comments cannot contain contractor response fields"
          )
        end
      elsif contractor?
        if admin_recommended_remedy.present?
          errors.add(:admin_recommended_remedy, "must be blank")
        end
        if contractor_response_method.blank?
          errors.add(:contractor_response_method, "is required")
        end
      end
    end

    def asserted_value_scope
      return if contractor_asserted_value.blank?
      if contractor? && contractor_response_method == "attestation_provided"
        return
      end

      errors.add(
        :contractor_asserted_value,
        "requires a contractor attestation"
      )
    end

    def issue_and_round_share_invoice
      return if revision_issue.blank? || revision_round.blank?
      return if revision_issue.invoice_id == revision_round.invoice_id

      errors.add(:base, "issue and round must belong to the same invoice")
    end
  end
end
