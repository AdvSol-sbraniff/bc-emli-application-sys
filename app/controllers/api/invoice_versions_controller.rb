# app/controllers/api/invoice_versions_controller.rb
module Api
  class InvoiceVersionsController < Api::ApplicationController
    # For the POC: don’t require login + don’t require policy checks
skip_before_action :authenticate_user!, only: %i[current_invoices read]
skip_before_action :require_confirmation, only: %i[current_invoices read]
skip_after_action :verify_authorized, only: %i[current_invoices read]



# used in the nav bar
# GET /api/sessions/:session_id/current_invoices
# Returns ordered invoice IDs for the session (based on current invoice_version created_at desc)
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

# GET /api/sessions/:session_id/invoices/:invoice_id/read
def read
  row = Claims::CurrentInvoiceVersion.find_by(
    session_id: params[:session_id],
    invoice_id: params[:invoice_id]
  )

  if row.nil?
    render json: {
      error: "Not found",
      session_id: params[:session_id],
      invoice_id: params[:invoice_id]
    }, status: :not_found
    return
  end

  render json: {
    read: Claims::CurrentInvoiceVersionBlueprint.render_as_hash(row, view: :read_screen)
  }
end



    
  end
end


