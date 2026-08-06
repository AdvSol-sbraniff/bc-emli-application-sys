# frozen_string_literal: true

module Api
  module Claims
    class ConversationMessagesAdminController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!,
                         only: %i[
                           index
                           show
                           create
                           update
                           destroy
                           mark_contractor_messages_read
                         ]
      skip_before_action :require_confirmation,
                         only: %i[
                           index
                           show
                           create
                           update
                           destroy
                           mark_contractor_messages_read
                         ]
      skip_after_action :verify_authorized,
                        only: %i[
                          index
                          show
                          create
                          update
                          destroy
                          mark_contractor_messages_read
                        ]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[
                                index
                                show
                                create
                                update
                                destroy
                                mark_contractor_messages_read
                              ]

      # GET /api/claims/admin/conversation_messages
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        session_id = params[:session_id].to_s.strip
        invoice_id = params[:invoice_id].to_s.strip
        sort =
          params[:sort].to_s.strip.presence ||
            "conversation_message_updated_at:desc"

        scope =
          ::Claims::ConversationMessageGrid.where.not(
            conversation_message_id: nil
          )

        scope = scope.where(session_id: session_id) if session_id.present?
        scope = scope.where(invoice_id: invoice_id) if invoice_id.present?

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
              CAST(claims.v_conversation_message_grid.session_id AS text) ILIKE :like
              OR CAST(claims.v_conversation_message_grid.invoice_id AS text) ILIKE :like
              OR CAST(claims.v_conversation_message_grid.invoice_version_id AS text) ILIKE :like
              OR CAST(claims.v_conversation_message_grid.conversation_message_id AS text) ILIKE :like
              OR claims.v_conversation_message_grid.conversation_message_type ILIKE :like
              OR claims.v_conversation_message_grid.conversation_message_text ILIKE :like
            SQL
        end

        scope = scope.order(order_clause(sort))

        total = scope.count
        rows = scope.offset((page - 1) * per).limit(per)
        rows_json = rows.as_json

        invoice_ids = rows_json.map { |r| r["invoice_id"] }.compact.uniq
        contractor_by_invoice = {}

        if invoice_ids.any?
          contractor_by_invoice =
            ::Claims::InvoiceGrid
              .where(invoice_id: invoice_ids)
              .pluck(:invoice_id, :contractor_business_name)
              .to_h
        end

        rows_json.each do |r|
          r["contractor_business_name"] = contractor_by_invoice[r["invoice_id"]]
        end

        render json: {
                 rows: rows_json,
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: sort,
                   filters: {
                     q: q.presence,
                     session_id: session_id.presence,
                     invoice_id: invoice_id.presence
                   }
                 }
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[CLAIMS][CONVERSATION_MESSAGE_GRID] ERROR: #{e.class}: #{e.message}"
        )
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /api/claims/admin/conversation_messages/:id
      def show
        record = ::Claims::ConversationMessage.find(params[:id])
        context = context_from_grid(record)
        render json: serialize_record(record).merge(context), status: :ok
      end

      # POST /api/claims/admin/conversation_messages
      def create
        attrs = create_params.to_h
        if attrs["invoice_id"].blank? && attrs["invoice_version_id"].present?
          attrs["invoice_id"] = ::Claims::InvoiceVersion.find(
            attrs["invoice_version_id"]
          ).invoice_id
        elsif attrs["invoice_id"].present?
          ::Claims::Invoice.find(attrs["invoice_id"])
        end

        attempts = 0

        begin
          record = ::Claims::ConversationMessage.new(attrs)
          record.save!
        rescue ActiveRecord::RecordNotUnique => e
          attempts += 1
          retry if attempts < 3
          raise e
        end

        render json: serialize_record(record), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound => e
        render json: { error: e.message }, status: :not_found
      rescue ActiveRecord::NotNullViolation, ActiveRecord::StatementInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # PATCH /api/claims/admin/conversation_messages/:id
      def update
        record = ::Claims::ConversationMessage.find(params[:id])
        record.update!(update_params)

        render json: serialize_record(record), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      # DELETE /api/claims/admin/conversation_messages/:id
      def destroy
        record = ::Claims::ConversationMessage.find(params[:id])
        record.destroy!

        render json: { id: record.id, deleted: true }, status: :ok
      end

      # POST /api/claims/admin/invoices/:invoice_id/conversation_messages/read
      def mark_contractor_messages_read
        invoice = ::Claims::Invoice.find(params[:invoice_id])
        requested_seqno = Integer(params[:through_seqno], exception: false)
        if requested_seqno.nil? || requested_seqno.negative?
          render json: {
                   error: "A non-negative through_seqno is required."
                 },
                 status: :unprocessable_entity
          return
        end

        message_scope =
          ::Claims::ConversationMessage.where(invoice_id: invoice.id)
        latest_contractor_seqno =
          message_scope
            .where(message_type: "contractor_note")
            .maximum(:revreq_seqno)
            .to_i
        through_seqno = [requested_seqno, latest_contractor_seqno].min
        message_scope
          .where(message_type: "contractor_note", recipient_read_at: nil)
          .where("revreq_seqno <= ?", through_seqno)
          .update_all(recipient_read_at: Time.current)
        unread_count =
          message_scope.where(
            message_type: "contractor_note",
            recipient_read_at: nil
          ).count

        render json: {
                 unread_count: unread_count,
                 latest_contractor_seqno: latest_contractor_seqno
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue StandardError => e
        Rails.logger.error(
          "[claims][conversation_messages_admin][mark_read] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def create_params
        params.permit(
          :invoice_id,
          :invoice_version_id,
          :requester_id,
          :message_type,
          :request_text
        )
      end

      def update_params
        params.permit(:message_type, :request_text)
      end

      def serialize_record(record)
        {
          id: record.id,
          invoice_id: record.invoice_id,
          invoice_version_id: record.invoice_version_id,
          revreq_seqno: record.revreq_seqno,
          requester_id: record.requester_id,
          message_type: record.message_type,
          request_text: record.request_text,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      end

      def context_from_grid(record)
        row =
          ::Claims::ConversationMessageGrid
            .where(conversation_message_id: record.id)
            .order(Arel.sql("conversation_message_updated_at DESC NULLS LAST"))
            .first

        return {} unless row

        contractor_name = nil
        if row.invoice_id.present?
          contractor_name =
            ::Claims::InvoiceGrid
              .where(invoice_id: row.invoice_id)
              .limit(1)
              .pluck(:contractor_business_name)
              .first
        end

        {
          session_id: row.session_id,
          session_created_at: row.session_created_at,
          invoice_id: row.invoice_id,
          contractor_business_name: contractor_name,
          invoice_version_created_at: row.invoice_version_created_at,
          invoice_versionno: row.invoice_versionno,
          di_ocr_invoice_id: row.di_ocr_invoice_id
        }
      end

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
          when "conversation_message_updated_at"
            "claims.v_conversation_message_grid.conversation_message_updated_at"
          when "conversation_message_created_at"
            "claims.v_conversation_message_grid.conversation_message_created_at"
          when "session_created_at"
            "claims.v_conversation_message_grid.session_created_at"
          when "invoice_version_updated_at"
            "claims.v_conversation_message_grid.invoice_version_updated_at"
          when "invoice_versionno"
            "claims.v_conversation_message_grid.invoice_versionno"
          else
            "claims.v_conversation_message_grid.conversation_message_updated_at"
          end

        Arel.sql("#{column} #{dir} NULLS LAST")
      end
    end
  end
end
