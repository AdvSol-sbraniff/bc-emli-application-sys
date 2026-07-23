# frozen_string_literal: true

module Api
  module Claims
    class InvoiceRevisionIssuesAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :require_confirmation
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped, only: :index
      skip_forgery_protection

      def index
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        render json: tracker(invoice), status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      end

      def create_issue
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        ::Claims::RevisionIssues::CreateIssue.call(
          invoice: invoice,
          attributes: issue_create_params
        )
        render json: tracker(invoice.reload), status: :created
      rescue ::Claims::RevisionIssues::CreateIssue::ClosedIssueExists,
             ::Claims::RevisionIssues::CreateIssue::AlreadyInRound,
             ::Claims::RevisionIssues::CreateIssue::SourceMismatch,
             ::Claims::RevisionIssues::EnsureDraftRound::RoundAlreadyActive,
             ::Claims::RevisionIssues::EnsureDraftRound::WrongInvoiceStatus => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordNotUnique
        render json: {
                 error: "This problem is already tracked"
               },
               status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e)
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "Invoice or source not found"
               },
               status: :not_found
      end

      def ensure_managed
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        version =
          invoice
            .invoice_versions
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .first!
        ::Claims::RevisionIssues::EnsureManagedIssues.call(
          invoice: invoice,
          invoice_version: version
        )
        render json: tracker(invoice.reload), status: :ok
      rescue ::Claims::RevisionIssues::EnsureManagedIssues::WrongInvoiceStatus,
             ::Claims::RevisionIssues::EnsureManagedIssues::StaleInvoiceVersion => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e)
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "Invoice or current package version not found"
               },
               status: :not_found
      end

      def update_comment
        invoice, comment = find_comment!
        ::Claims::RevisionIssues::UpdateAdminComment.call(
          comment: comment,
          attributes: admin_comment_params
        )
        render json: tracker(invoice.reload), status: :ok
      rescue ActiveRecord::ReadOnlyRecord => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Revision comment not found" }, status: :not_found
      end

      def save_admin_comment
        invoice, issue = find_issue!
        ::Claims::RevisionIssues::SaveAdminComment.call(
          issue: issue,
          attributes: admin_comment_params
        )
        render json: tracker(invoice.reload), status: :ok
      rescue ::Claims::RevisionIssues::EnsureDraftRound::RoundAlreadyActive,
             ::Claims::RevisionIssues::EnsureDraftRound::WrongInvoiceStatus,
             ActiveRecord::ReadOnlyRecord => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Revision issue not found" }, status: :not_found
      end

      def reset_comment
        invoice, comment = find_comment!
        ::Claims::RevisionIssues::ResetAdminComment.call(comment: comment)
        render json: tracker(invoice.reload), status: :ok
      rescue ActiveRecord::ReadOnlyRecord => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Revision comment not found" }, status: :not_found
      end

      def destroy_issue
        invoice, issue = find_issue!
        ::Claims::RevisionIssues::DeleteUnsentIssue.call(issue: issue)
        render json: tracker(invoice.reload), status: :ok
      rescue ActiveRecord::ReadOnlyRecord => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Revision issue not found" }, status: :not_found
      end

      def send_issues
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        round = invoice.revision_rounds.newest_first.first!
        ::Claims::RevisionIssues::SendRound.call(
          revision_round: round,
          actor_user_id: current_user&.id
        )
        render json: tracker(invoice.reload), status: :ok
      rescue ::Claims::RevisionIssues::SendRound::Incomplete => e
        render json: {
                 error: e.message,
                 details: e.details
               },
               status: :unprocessable_entity
      rescue ActiveRecord::ReadOnlyRecord => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "No revision issues are ready to send"
               },
               status: :not_found
      end

      def close_issue
        invoice, issue = find_issue!
        ::Claims::RevisionIssues::CloseIssue.call(
          issue: issue,
          status: params[:status],
          disposition_comment: params[:disposition_comment]
        )
        render json: tracker(invoice.reload), status: :ok
      rescue ActiveRecord::ReadOnlyRecord => e
        render json: { error: e.message }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e)
      rescue ActiveRecord::RecordNotFound
        render json: {
                 error: "Revision issue or round not found"
               },
               status: :not_found
      end

      private

      def find_issue!
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        [invoice, invoice.revision_issues.find(params[:issue_id])]
      end

      def find_comment!
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        comment =
          ::Claims::RevisionIssueComment
            .joins(:revision_issue)
            .where(
              :id => params[:comment_id],
              "claims.revision_issues" => {
                invoice_id: invoice.id
              }
            )
            .first!
        [invoice, comment]
      end

      def issue_create_params
        params.permit(
          :issue_type,
          :invoice_version_rulecheck_id,
          :invoice_version_located_field_id,
          :supporting_document_located_field_id,
          :di_field_key
        )
      end

      def admin_comment_params
        params.permit(:admin_recommended_remedy, :comment_text)
      end

      def tracker(invoice)
        ::Claims::RevisionIssues::SerializeTracker.call(
          invoice: invoice,
          role: :admin
        )
      end

      def render_invalid(error)
        render json: {
                 error: error.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end
    end
  end
end
