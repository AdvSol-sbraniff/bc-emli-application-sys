# frozen_string_literal: true
# /app/controllers/api/claims/sessions_with_contractors_admin_controller.rb
module Api
  module Claims
    class SessionsWithContractorsAdminController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      # TEMP: allow local dev to hit this without auth until KC is wired
      skip_before_action :authenticate_user!, only: %i[index destroy]
      skip_before_action :require_confirmation, only: %i[index destroy]
      skip_after_action :verify_authorized, only: %i[index destroy]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index destroy]

      # GET /api/claims/admin/sessions_with_contractors?q=&status=&sort=&page=&per=
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "updated_at:desc"

        # View lives in claims schema
        scope = ::Claims::VSessionWithContractor.all

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
              CAST(claims.v_sessions_with_contractors.id AS text) ILIKE :like
              OR CAST(claims.v_sessions_with_contractors.contractor_id AS text) ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_business_name ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_number ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_email ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_phone_number ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_cellphone_number ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_city ILIKE :like
              OR claims.v_sessions_with_contractors.contractor_postal_code ILIKE :like
            SQL
        end

        scope = scope.order(order_clause(sort))
        total = scope.count

        sessions = scope.offset((page - 1) * per).limit(per)

        rows =
          sessions.map do |s|
            {
              # session fields (from s.* in the view)
              id: s.id,
              contractor_id: s.contractor_id,
              submitter_id: s.submitter_id,
              created_at: s.created_at,
              updated_at: s.updated_at,
              submitted_at: s.submitted_at,
              # denormalized contractor fields (aliased in the view)
              contractor_business_name: s.contractor_business_name,
              contractor_number: s.contractor_number,
              contractor_email: s.contractor_email,
              contractor_phone_number: s.contractor_phone_number,
              contractor_cellphone_number: s.contractor_cellphone_number,
              contractor_city: s.contractor_city,
              contractor_postal_code: s.contractor_postal_code,
              contractor_onboarded: s.contractor_onboarded
            }
          end

        render json: {
                 rows: rows,
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: sort,
                   filters: {
                     q: q.presence
                   }
                 }
               }
      end

      # DELETE /api/claims/admin/sessions_with_contractors/:id
      # Deletes a session and all claim artifacts beneath it in FK-safe order.
      def destroy
        session = ::Claims::Session.find(params[:id])

        deleted = {
          session_id: session.id,
          invoices: 0,
          invoice_versions: 0,
          lineitems: 0,
          revision_rounds: 0,
          revision_issues: 0,
          revision_issue_comments: 0,
          conversation_messages: 0,
          supporting_documents: 0,
          ingest_runs: 0,
          ingest_step_runs: 0
        }

        ::Claims::Session.transaction do
          invoice_ids =
            ::Claims::Invoice.where(session_id: session.id).pluck(:id)
          invoice_version_ids =
            if invoice_ids.any?
              ::Claims::InvoiceVersion.where(invoice_id: invoice_ids).pluck(:id)
            else
              []
            end

          if invoice_ids.any?
            deleted[
              :conversation_messages
            ] = ::Claims::ConversationMessage.where(
              invoice_id: invoice_ids
            ).delete_all
          end

          if invoice_ids.any?
            deleted[:revision_issue_comments] = ::Claims::RevisionIssueComment
              .joins(:revision_issue)
              .where("claims.revision_issues" => { invoice_id: invoice_ids })
              .delete_all
            deleted[:revision_issues] = ::Claims::RevisionIssue.where(
              invoice_id: invoice_ids
            ).delete_all
            deleted[:revision_rounds] = ::Claims::RevisionRound.where(
              invoice_id: invoice_ids
            ).delete_all
          end

          if invoice_version_ids.any?
            deleted[:lineitems] = ::Claims::Lineitem.where(
              invoice_version_id: invoice_version_ids
            ).delete_all
            # These also cascade from invoice_versions, but explicit deletes keep counts accurate.
            ::Claims::InvoiceVersionLocatedField.where(
              invoice_version_id: invoice_version_ids
            ).delete_all
            ::Claims::InvoiceVersionRulecheck.where(
              invoice_version_id: invoice_version_ids
            ).delete_all
            deleted[:ingest_step_runs] += ::Claims::IngestStepRun.where(
              invoice_version_id: invoice_version_ids
            ).delete_all
          end

          if invoice_version_ids.any?
            supporting_document_ids =
              ::Claims::SupportingDocument.where(
                invoice_version_id: invoice_version_ids
              ).pluck(:id)
            ::Claims::SupportingDocumentLocatedField.where(
              supporting_document_id: supporting_document_ids
            ).delete_all
            ::Claims::SupportingDocumentVisualFinding.where(
              supporting_document_id: supporting_document_ids
            ).delete_all
            deleted[:supporting_documents] = ::Claims::SupportingDocument.where(
              id: supporting_document_ids
            ).delete_all
          end

          # Clean run trackers tied to this session before removing invoices/session.
          deleted[:ingest_step_runs] += ::Claims::IngestStepRun.where(
            session_id: session.id
          ).delete_all
          deleted[:ingest_runs] = ::Claims::IngestRun.where(
            session_id: session.id
          ).delete_all

          deleted[:invoice_versions] = ::Claims::InvoiceVersion.where(
            invoice_id: invoice_ids
          ).delete_all if invoice_ids.any?
          deleted[:invoices] = ::Claims::Invoice.where(
            id: invoice_ids
          ).delete_all if invoice_ids.any?

          session.destroy!
        end

        render json: { deleted: true, counts: deleted }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Session not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[CLAIMS][SESSIONS_ADMIN] destroy failed id=#{params[:id]}: #{e.class}: #{e.message}"
        )
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def clamp_int(value, default, min, max)
        n =
          begin
            Integer(value)
          rescue StandardError
            default
          end
        n = default if n.nil?
        n = min if n < min
        n = max if n > max
        n
      end

      def sanitize_sql_like(string)
        string.to_s.gsub(/[\\%_]/) { |x| "\\#{x}" }
      end

      def order_clause(sort)
        key, dir = sort.to_s.split(":", 2)
        dir = dir&.downcase == "asc" ? "ASC" : "DESC"

        column =
          case key
          when "created_at"
            "claims.v_sessions_with_contractors.created_at"
          when "updated_at"
            "claims.v_sessions_with_contractors.updated_at"
          when "submitted_at"
            "claims.v_sessions_with_contractors.submitted_at"
          when "contractor_business_name"
            "claims.v_sessions_with_contractors.contractor_business_name"
          when "contractor_number"
            "claims.v_sessions_with_contractors.contractor_number"
          when "contractor_city"
            "claims.v_sessions_with_contractors.contractor_city"
          when "contractor_onboarded"
            "claims.v_sessions_with_contractors.contractor_onboarded"
          else
            "claims.v_sessions_with_contractors.updated_at"
          end

        Arel.sql("#{column} #{dir}")
      end
    end
  end
end
