# frozen_string_literal: true
# /app/controllers/api/claims/contractors_admin_controller.rb
module Api
  module Claims
    class ContractorsAdminController < ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      # TEMP: allow local dev to hit this without auth until KC is wired
      skip_before_action :authenticate_user!,
                         only: %i[index show create update destroy]
      skip_before_action :require_confirmation,
                         only: %i[index show create update destroy]
      skip_after_action :verify_authorized,
                        only: %i[index show create update destroy]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[index show create update destroy]

      # GET /api/claims/admin/contractors?q=&sort=&page=&per=
      def index
        per = clamp_int(params[:per], 25, 1, 100)
        page = clamp_int(params[:page], 1, 1, 10_000)
        q = params[:q].to_s.strip
        sort = params[:sort].to_s.strip.presence || "business_name:asc"

        scope = ::Contractor.all

        if q.present?
          like = "%#{sanitize_sql_like(q)}%"
          scope = scope.where(<<~SQL.squish, like: like)
              contractors.business_name ILIKE :like
              OR contractors.number ILIKE :like
              OR contractors.email ILIKE :like
              OR contractors.phone_number ILIKE :like
              OR contractors.cellphone_number ILIKE :like
              OR contractors.city ILIKE :like
              OR contractors.postal_code ILIKE :like
            SQL
        end

        scope = scope.order(order_clause(sort))
        total = scope.count

        contractors = scope.offset((page - 1) * per).limit(per)

        rows = contractors.map { |contractor| serialize_contractor(contractor) }

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

      # GET /api/claims/admin/contractors/:id
      def show
        render json: serialize_contractor(find_contractor), status: :ok
      end

      # POST /api/claims/admin/contractors
      def create
        contractor = ::Contractor.new(contractor_params)
        contractor.save!

        render json: serialize_contractor(contractor), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      # PATCH /api/claims/admin/contractors/:id
      def update
        contractor = find_contractor
        contractor.update!(contractor_params)

        render json: serialize_contractor(contractor), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      end

      # DELETE /api/claims/admin/contractors/:id
      def destroy
        contractor = find_contractor
        contractor.destroy!

        render json: { ok: true, id: contractor.id }, status: :ok
      rescue ActiveRecord::InvalidForeignKey
        render json: {
                 error:
                   "This contractor is referenced by other records and cannot be deleted."
               },
               status: :unprocessable_entity
      end

      private

      def find_contractor
        ::Contractor.find(params[:id])
      end

      def contractor_params
        permitted =
          params.permit(
            :contact_id,
            :business_name,
            :number,
            :website,
            :phone_number,
            :cellphone_number,
            :street_address,
            :city,
            :postal_code,
            :email,
            :onboarded
          )

        normalize_contractor_params(permitted)
      end

      def normalize_contractor_params(permitted)
        attrs = permitted.to_h

        attrs.transform_values! do |value|
          value.is_a?(String) && value.strip.blank? ? nil : value
        end

        attrs["onboarded"] = ActiveModel::Type::Boolean.new.cast(
          attrs["onboarded"]
        ) if attrs.key?("onboarded")
        attrs
      end

      def serialize_contractor(contractor)
        {
          id: contractor.id,
          contact_id: contractor.contact_id,
          business_name: contractor.business_name,
          contractor_number: contractor.number,
          number: contractor.number,
          website: contractor.website,
          # Contractor#email is overridden to return contact.email, so read the column directly here.
          email: contractor.read_attribute(:email),
          contact_email: contractor.contact&.email,
          contact_name: contractor.contact&.name,
          phone_number: contractor.phone_number,
          cellphone_number: contractor.cellphone_number,
          street_address: contractor.street_address,
          city: contractor.city,
          postal_code: contractor.postal_code,
          onboarded: contractor.onboarded,
          created_at: contractor.created_at,
          updated_at: contractor.updated_at
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
        dir = dir&.downcase == "desc" ? "DESC" : "ASC"

        column =
          case key
          when "business_name"
            "contractors.business_name"
          when "number"
            "contractors.number"
          when "email"
            "contractors.email"
          when "created_at"
            "contractors.created_at"
          when "updated_at"
            "contractors.updated_at"
          else
            "contractors.business_name"
          end

        Arel.sql("#{column} #{dir}")
      end
    end
  end
end
