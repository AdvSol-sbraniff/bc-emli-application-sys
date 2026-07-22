# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SerializeTracker
      def self.call(**args)
        new(**args).call
      end

      def initialize(invoice:, role:)
        @invoice = invoice
        @role = role.to_sym
      end

      def call
        rounds = round_scope.includes(:invoice_version).newest_first.to_a
        issues = issue_scope.to_a
        preload_issue_sources(issues)
        comments =
          comment_scope(issues, rounds)
            .includes(:revision_round, :revision_issue)
            .order(:created_at, :id)
            .to_a
        comments_by_issue = comments.group_by(&:revision_issue_id)
        latest = rounds.first
        sorted_issues =
          issues.sort_by do |issue|
            [issue.unresolved? ? 0 : 1, issue.created_at, issue.id]
          end

        {
          invoice_id: @invoice.id,
          invoice_status: @invoice.status,
          invoice_status_subtype: @invoice.status_subtype,
          latest_round_id: latest&.id,
          rounds: rounds.map { |round| serialize_round(round) },
          issues:
            sorted_issues.map do |issue|
              serialize_issue(
                issue,
                comments: comments_by_issue.fetch(issue.id, []),
                latest_round: latest
              )
            end,
          suppressed_source_identities: suppressed_source_identities,
          capabilities: capabilities(latest)
        }
      end

      private

      def round_scope
        scope = @invoice.revision_rounds
        contractor? ? scope.where.not(admin_sent_at: nil) : scope
      end

      def issue_scope
        scope = @invoice.revision_issues
        return scope unless contractor?

        scope.contractor_visible
      end

      def suppressed_source_identities
        return [] unless contractor?

        @invoice
          .revision_issues
          .where(status: "closed_no_contractor_action_required")
          .order(:created_at, :id)
          .map { |issue| SourceIdentity.serialize(issue) }
      end

      def comment_scope(issues, rounds)
        ::Claims::RevisionIssueComment.where(
          revision_issue_id: issues.map(&:id),
          revision_round_id: rounds.map(&:id)
        )
      end

      def serialize_round(round)
        {
          id: round.id,
          invoice_version_id: round.invoice_version_id,
          invoice_versionno: round.invoice_version.invoice_versionno,
          original_filename: round.invoice_version.original_filename,
          round_number: round.round_number,
          state: round_state(round),
          admin_sent_at: round.admin_sent_at,
          contractor_response_submitted_at:
            round.contractor_response_submitted_at,
          created_at: round.created_at
        }
      end

      def serialize_issue(issue, comments:, latest_round:)
        source = SourcePresenter.call(issue)
        source = source.except(:source_key, :source_engine) if contractor?
        in_latest_round =
          latest_round.present? &&
            comments.any? do |comment|
              comment.revision_round_id == latest_round.id
            end
        has_sent_history =
          comments.any? do |comment|
            comment.revision_round.admin_sent_at.present?
          end
        editable_admin_comment =
          comments.reverse.find do |comment|
            admin? && comment.admin? && latest_round&.draft? &&
              comment.revision_round_id == latest_round.id
          end
        can_admin_comment =
          admin? && issue.unresolved? &&
            @invoice.status == "admin_review_inbox" &&
            !latest_round&.waiting_for_contractor?
        suggested =
          if can_admin_comment && editable_admin_comment.nil?
            suggested_admin_comment
          end
        {
          id: issue.id,
          issue_type: issue.issue_type,
          status: issue.status,
          disposition_comment: issue.disposition_comment,
          created_at: issue.created_at,
          updated_at: issue.updated_at,
          in_latest_round: in_latest_round,
          can_delete:
            admin? && issue.pending_admin_review? && latest_round&.draft? &&
              in_latest_round && !has_sent_history,
          can_close:
            admin? && issue.unresolved? &&
              @invoice.status == "admin_review_inbox" &&
              latest_round.present? && !latest_round.waiting_for_contractor?,
          can_admin_comment: can_admin_comment,
          suggested_admin_comment: suggested,
          can_contractor_respond:
            contractor? && issue.open? &&
              latest_round&.waiting_for_contractor? &&
              comments.any? do |comment|
                comment.revision_round_id == latest_round.id &&
                  comment.admin_recommended_remedy.present?
              end,
          source_reference: admin? ? issue.source_reference : nil,
          source_identity: SourceIdentity.serialize(issue),
          source: source,
          comments:
            comments.map do |comment|
              serialize_comment(comment, latest_round: latest_round)
            end
        }.compact
      end

      def serialize_comment(comment, latest_round:)
        {
          id: comment.id,
          revision_issue_id: comment.revision_issue_id,
          revision_round_id: comment.revision_round_id,
          round_number: comment.revision_round.round_number,
          author_type: comment.author_type,
          admin_recommended_remedy: comment.admin_recommended_remedy,
          contractor_response_method: comment.contractor_response_method,
          comment_text: comment.comment_text,
          contractor_asserted_value: comment.contractor_asserted_value,
          created_at: comment.created_at,
          updated_at: comment.updated_at,
          can_edit:
            (
              admin? && comment.admin? && latest_round&.draft? &&
                comment.revision_round_id == latest_round.id &&
                comment.revision_issue.unresolved?
            ) ||
              (
                contractor? && comment.contractor? &&
                  latest_round&.waiting_for_contractor? &&
                  comment.revision_round_id == latest_round.id &&
                  comment.revision_issue.open?
              )
        }
      end

      def capabilities(latest)
        if contractor?
          if latest.present?
            coverage = ContractorResponseCoverage.call(round: latest)
          end
          return(
            {
              can_submit_response:
                latest&.waiting_for_contractor? && coverage&.complete? || false,
              incomplete_issue_ids: coverage&.incomplete_issue_ids || [],
              document_upload_required_issue_ids:
                coverage&.document_upload_required_issue_ids || []
            }
          )
        end

        missing_admin_issue_ids = missing_admin_comment_issue_ids(latest)
        {
          can_send_issues:
            @invoice.status == "admin_review_inbox" && latest&.draft? &&
              @invoice.revision_issues.unresolved_issues.exists? &&
              missing_admin_issue_ids.empty?,
          can_add_issue:
            @invoice.status == "admin_review_inbox" &&
              !latest&.waiting_for_contractor?,
          missing_admin_comment_issue_ids: missing_admin_issue_ids
        }
      end

      def missing_admin_comment_issue_ids(round)
        unresolved_ids = @invoice.revision_issues.unresolved_issues.pluck(:id)
        return unresolved_ids unless round&.draft?

        complete_ids =
          round
            .comments
            .where(author_type: "admin", revision_issue_id: unresolved_ids)
            .where.not(admin_recommended_remedy: nil)
            .where.not(comment_text: [nil, ""])
            .pluck(:revision_issue_id)
        unresolved_ids - complete_ids
      end

      def suggested_admin_comment
        { admin_recommended_remedy: nil, comment_text: "" }
      end

      def round_state(round)
        return "draft" if round.draft?
        return "awaiting_contractor" if round.waiting_for_contractor?

        "response_submitted"
      end

      def preload_issue_sources(issues)
        associations = {
          "rule" => {
            opened_from_invoice_version_rulecheck: :invoice_version
          },
          "invoice_field" => {
            opened_from_invoice_version_located_field: :invoice_version
          },
          "supporting_document_field" => {
            opened_from_supporting_document_located_field: [
              { supporting_document: :supporting_document_type },
              :supporting_document_type_located_field
            ]
          },
          "di_field" => :opened_from_di_invoice_version
        }
        associations.each do |issue_type, association|
          records = issues.select { |issue| issue.issue_type == issue_type }
          next if records.empty?

          ActiveRecord::Associations::Preloader.new(
            records: records,
            associations: association
          ).call
        end
      end

      def contractor?
        @role == :contractor
      end

      def admin?
        @role == :admin
      end
    end
  end
end
