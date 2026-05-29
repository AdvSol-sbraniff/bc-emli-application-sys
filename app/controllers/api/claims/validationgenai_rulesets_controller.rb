# app/controllers/api/claims/validationgenai_rulesets_controller.rb
module Api
  module Claims
    class ValidationgenaiRulesetsController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      # POC: mirror your SessionsController approach (no auth for now)
      skip_before_action :verify_authenticity_token,
                         only: %i[
                           index
                           show
                           create
                           update
                           config_show
                           config_update
                           upgrade_types
                         ]
      skip_before_action :authenticate_user!,
                         only: %i[
                           index
                           show
                           create
                           update
                           config_show
                           config_update
                           upgrade_types
                         ]
      skip_before_action :require_confirmation,
                         only: %i[
                           index
                           show
                           create
                           update
                           config_show
                           config_update
                           upgrade_types
                         ]
      skip_after_action :verify_authorized,
                        only: %i[
                          index
                          show
                          create
                          update
                          config_show
                          config_update
                          upgrade_types
                        ]
      skip_after_action :verify_policy_scoped, only: %i[index upgrade_types]

      # GET /api/claims/admin/validationgenai_rulesets/:id
      def show
        ruleset = ruleset_scope.find(params[:id])

        render json: serialize_ruleset(ruleset), status: :ok
      end

      # PATCH /api/claims/admin/validationgenai_rulesets/:id
      # Body: { ruleset_shortname, user_record1 }
      def update
        ruleset = ::Claims::ValidationgenaiRuleset.find(params[:id])

        ruleset.update!(update_params)

        render json: serialize_ruleset(ruleset_scope.find(ruleset.id)),
               status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      # POST /api/claims/admin/validationgenai_rulesets
      # Body: { ruleset_shortname, invoice_upgrade_type_id, user_record1 }
      def create
        ruleset = ::Claims::ValidationgenaiRuleset.new(create_params)
        ruleset.save!

        render json: serialize_ruleset(ruleset_scope.find(ruleset.id)),
               status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      # GET /api/claims/admin/validationgenai_rulesets?q=&sort=&page=&per=
      def index
        per = clamp_int(params[:per], 25, 1, 200)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "created_at:desc"
        invoice_upgrade_type_id =
          params[:invoice_upgrade_type_id].to_s.strip.presence
        current_only =
          ActiveModel::Type::Boolean.new.cast(params.fetch(:current_only, true))

        scope = ruleset_scope

        if invoice_upgrade_type_id.present?
          scope =
            scope.where(
              "claims.validationgenai_rulesets.invoice_upgrade_type_id = ?",
              invoice_upgrade_type_id
            )
        end

        current_ids = current_ruleset_ids
        scope = scope.where(id: current_ids) if current_only

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
              CAST(claims.validationgenai_rulesets.id AS text) ILIKE :like
              OR claims.validationgenai_rulesets.ruleset_shortname ILIKE :like
              OR claims.validationgenai_rulesets.user_record1 ILIKE :like
              OR claims.invoice_upgrade_types.upgrade_type_key ILIKE :like
              OR claims.invoice_upgrade_types.description ILIKE :like
            SQL
        end

        scope = scope.order(order_clause(sort))
        total = scope.except(:select, :order).count

        rulesets = scope.offset((page - 1) * per).limit(per)

        render json: {
                 rows:
                   rulesets.map do |r|
                     serialize_ruleset(r, current_ids: current_ids)
                   end,
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: sort,
                   filters: {
                     q: q.presence,
                     invoice_upgrade_type_id: invoice_upgrade_type_id,
                     current_only: current_only
                   }
                 }
               }
      end

      # GET /api/claims/admin/invoice_upgrade_types
      def upgrade_types
        rows =
          ::Claims::InvoiceUpgradeType
            .joins(
              "JOIN claims.validationgenai_rulesets r ON r.invoice_upgrade_type_id = claims.invoice_upgrade_types.id"
            )
            .select("DISTINCT claims.invoice_upgrade_types.*")
            .order(:upgrade_type_key)
            .map do |t|
              {
                id: t.id,
                upgrade_type_key: t.upgrade_type_key,
                description: t.description
              }
            end

        render json: { rows: rows }, status: :ok
      end

      # GET /api/claims/admin/validationgenai_config
      def config_show
        render json: serialize_config(current_config), status: :ok
      end

      # PATCH /api/claims/admin/validationgenai_config
      def config_update
        config = current_config
        config.update!(config_params)

        render json: serialize_config(config), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      private

      def ruleset_scope
        ::Claims::ValidationgenaiRuleset.joins(
          "JOIN claims.invoice_upgrade_types ON claims.invoice_upgrade_types.id = claims.validationgenai_rulesets.invoice_upgrade_type_id"
        ).select(
          "claims.validationgenai_rulesets.*",
          "claims.invoice_upgrade_types.upgrade_type_key AS upgrade_type_key",
          "claims.invoice_upgrade_types.description AS upgrade_type_description"
        )
      end

      def current_ruleset_ids
        ::Claims::ValidationgenaiRuleset
          .select(
            "DISTINCT ON (invoice_upgrade_type_id) claims.validationgenai_rulesets.id"
          )
          .order(
            Arel.sql(
              "invoice_upgrade_type_id, updated_at DESC, created_at DESC, id DESC"
            )
          )
          .map(&:id)
      end

      def current_config
        ::Claims::ValidationgenaiConfig.order(:created_at).first ||
          ::Claims::ValidationgenaiConfig.create!(
            system_record: "",
            classifier_combined_with_extraction_system_record: "",
            classifier_without_extraction_system_record: "",
            supporting_document_extraction_system_record: "",
            supporting_document_extraction_mode: "combined_with_classifier",
            user_record0: "",
            admin_advice_intro: "",
            admin_advice_closing: "",
            created_at: Time.current,
            updated_at: Time.current
          )
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
          when "created_at"
            "claims.validationgenai_rulesets.created_at"
          when "updated_at"
            "claims.validationgenai_rulesets.updated_at"
          when "ruleset_shortname"
            "claims.validationgenai_rulesets.ruleset_shortname"
          when "upgrade_type_key"
            "claims.invoice_upgrade_types.upgrade_type_key"
          else
            "claims.validationgenai_rulesets.created_at"
          end

        Arel.sql("#{column} #{dir}")
      end

      def update_params
        params.permit(:ruleset_shortname, :user_record1)
      end

      def create_params
        params.permit(
          :ruleset_shortname,
          :invoice_upgrade_type_id,
          :user_record1
        )
      end

      def config_params
        attrs = {}
        %i[
          system_record
          classifier_combined_with_extraction_system_record
          classifier_without_extraction_system_record
          supporting_document_extraction_system_record
          supporting_document_extraction_mode
          user_record0
          admin_advice_intro
          admin_advice_closing
        ].each { |key| attrs[key] = params[key] if params.key?(key) }
        attrs
      end

      def serialize_ruleset(r, current_ids: nil)
        current_ids ||= current_ruleset_ids

        {
          id: r.id,
          invoice_upgrade_type_id: r.invoice_upgrade_type_id,
          upgrade_type_key:
            r.respond_to?(:upgrade_type_key) ? r.upgrade_type_key : nil,
          upgrade_type_description:
            (
              if r.respond_to?(:upgrade_type_description)
                r.upgrade_type_description
              else
                nil
              end
            ),
          ruleset_shortname: r.ruleset_shortname,
          user_record1: r.user_record1,
          is_current: current_ids.map(&:to_s).include?(r.id.to_s),
          created_at: r.created_at,
          updated_at: r.updated_at
        }
      end

      def serialize_config(c)
        {
          id: c.id,
          system_record: c.system_record,
          classifier_combined_with_extraction_system_record:
            c.classifier_combined_with_extraction_system_record,
          classifier_without_extraction_system_record:
            c.classifier_without_extraction_system_record,
          supporting_document_extraction_system_record:
            c.supporting_document_extraction_system_record,
          supporting_document_extraction_mode:
            c.supporting_document_extraction_mode,
          user_record0: c.user_record0,
          admin_advice_intro: c.admin_advice_intro,
          admin_advice_closing: c.admin_advice_closing,
          created_at: c.created_at,
          updated_at: c.updated_at
        }
      end
    end
  end
end
