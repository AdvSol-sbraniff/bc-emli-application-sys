# app/controllers/api/claims/invoice_versions_controller.rb
module Api
  module Claims
    class InvoiceVersionsController < Api::ApplicationController
      # For the POC: don’t require login + don’t require policy checks
      skip_before_action :authenticate_user!, only: %i[current_invoices read read_genai]
      skip_before_action :require_confirmation, only: %i[current_invoices read read_genai]
      skip_after_action  :verify_authorized,   only: %i[current_invoices read read_genai]

      # ============================================================
      # GET /api/claims/sessions/:session_id/current_invoices
      # PURPOSE: Nav bar list for a session (returns invoice_ids in display order)
      # ============================================================
      def current_invoices
        session_id = params[:session_id]

        sql = <<~SQL
          SELECT invoice_id
          FROM claims.v_current_invoice_versions
          WHERE session_id = ?
          ORDER BY created_at DESC
        SQL

        sanitized = ActiveRecord::Base.send(:sanitize_sql_array, [sql, session_id])
        rows = ActiveRecord::Base.connection.exec_query(sanitized, "current_invoices")
        invoice_ids = rows.rows.flatten

        render json: { invoice_ids: invoice_ids }
      end

      # ============================================================
      # GET /api/claims/sessions/:session_id/invoices/:invoice_id/read
      # PURPOSE: Read-screen payload for one invoice (resolves to *current* invoice_version)
      # ============================================================
      def read
        row = ::Claims::CurrentInvoiceVersion.find_by(
          session_id: params[:session_id],
          invoice_id: params[:invoice_id]
        )

        if row.nil?
          render json: { error: "Not found", session_id: params[:session_id], invoice_id: params[:invoice_id] }, status: :not_found
          return
        end

        render json: { read: ::Claims::CurrentInvoiceVersionBlueprint.render_as_hash(row, view: :read_screen) }
      end

      # ============================================================
      # GET /api/claims/sessions/:session_id/invoices/:invoice_id/read_genai
      # PURPOSE: GenAI located fields for the *current* invoice_version of an invoice
      # ============================================================
      def read_genai
        civ = ::Claims::CurrentInvoiceVersion.find_by(
          session_id: params[:session_id],
          invoice_id: params[:invoice_id]
        )

        if civ.nil?
          render json: { error: "Not found", session_id: params[:session_id], invoice_id: params[:invoice_id] }, status: :not_found
          return
        end

        rows = ::Claims::InvoiceVersionLocatedField
          .where(invoice_version_id: civ.id, source_engine: "genai")
          .order(:field_key, :line_number, :created_at)

        render json: {
          invoice_version_id: civ.id,
          located_fields: rows.as_json(
            only: [
              :id, :field_key, :line_number,
              :value_type, :value_text, :value_json, :normalized_value,
              :confidence, :page, :polygon,
              :evidence_text, :evidence_hint, :notes,
              :created_at, :updated_at
            ]
          )
        }
      end
    end
  end
end
