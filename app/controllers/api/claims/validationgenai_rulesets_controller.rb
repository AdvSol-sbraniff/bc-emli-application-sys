# app/controllers/api/claims/validationgenai_rulesets_controller.rb
module Api
  module Claims
    class ValidationgenaiRulesetsController < Api::ApplicationController
      # POC: mirror your SessionsController approach (no auth for now)
    skip_before_action :verify_authenticity_token, only: %i[index show create update]
    skip_before_action :authenticate_user!, only: %i[index show create update]
    skip_before_action :require_confirmation, only: %i[index show create update]
    skip_after_action  :verify_authorized, only: %i[index show create update]
skip_after_action  :verify_policy_scoped, only: %i[index]

      # GET /api/claims/admin/validationgenai_rulesets/:id
      def show
        ruleset = ::Claims::ValidationgenaiRuleset.find(params[:id])

        render json: serialize_ruleset(ruleset), status: :ok
      end

      # PATCH /api/claims/admin/validationgenai_rulesets/:id
      # Body: { ruleset_shortname, system_record, user_record1 }
      def update
        ruleset = ::Claims::ValidationgenaiRuleset.find(params[:id])

        ruleset.update!(update_params)

        render json: serialize_ruleset(ruleset), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      # POST /api/claims/admin/validationgenai_rulesets
      # Body: { ruleset_shortname, system_record, user_record1 }
      def create
        ruleset = ::Claims::ValidationgenaiRuleset.new(update_params)
        ruleset.save!

        render json: serialize_ruleset(ruleset), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

# GET /api/claims/admin/validationgenai_rulesets?q=&sort=&page=&per=
def index
  per  = clamp_int(params[:per], 25, 1, 200)
  page = clamp_int(params[:page], 1, 1, 10_000)
  q    = params[:q].to_s.strip
  sort = params[:sort].to_s.strip.presence || "created_at:desc"

  scope = ::Claims::ValidationgenaiRuleset.all

  if q.present?
    like = "%#{sanitize_sql_like(q)}%"
    scope = scope.where(
      <<~SQL.squish,
        CAST(claims.validationgenai_rulesets.id AS text) ILIKE :like
        OR claims.validationgenai_rulesets.ruleset_shortname ILIKE :like
        OR claims.validationgenai_rulesets.system_record ILIKE :like
        OR claims.validationgenai_rulesets.user_record1 ILIKE :like
      SQL
      like: like
    )
  end

  scope = scope.order(order_clause(sort))
  total = scope.count

  rulesets = scope
    .offset((page - 1) * per)
    .limit(per)

  rows = rulesets.map { |r| serialize_ruleset(r) }

  render json: {
    rows: rows,
    meta: {
      total: total,
      page: page,
      per: per,
      sort: sort,
      filters: { q: q.presence }
    }
  }
end



      private

def clamp_int(value, default, min, max)
  n = Integer(value) rescue default
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
    when "created_at"       then "claims.validationgenai_rulesets.created_at"
    when "updated_at"       then "claims.validationgenai_rulesets.updated_at"
    when "ruleset_shortname" then "claims.validationgenai_rulesets.ruleset_shortname"
    else
      "claims.validationgenai_rulesets.created_at"
    end

  Arel.sql("#{column} #{dir}")
end

      def update_params
        params.permit(:ruleset_shortname, :system_record, :user_record1)
      end

      def serialize_ruleset(r)
        {
          id: r.id,
          ruleset_shortname: r.ruleset_shortname,
          system_record: r.system_record,
          user_record1: r.user_record1,
          created_at: r.created_at,
          updated_at: r.updated_at
        }
      end
    end
  end
end