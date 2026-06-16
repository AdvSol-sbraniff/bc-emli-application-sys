# frozen_string_literal: true

module Api
  module Claims
    class ValidationgenaiConfigController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :verify_authenticity_token, only: %i[show update]
      skip_before_action :authenticate_user!, only: %i[show update]
      skip_before_action :require_confirmation, only: %i[show update]
      skip_after_action :verify_authorized, only: %i[show update]

      def show
        render json: serialize_config(current_config), status: :ok
      end

      def update
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

      def current_config
        ::Claims::ValidationgenaiConfig.order(:created_at).first ||
          ::Claims::ValidationgenaiConfig.create!(
            system_record: "",
            classifier_system_record: "",
            classifier_pdf_system_record: "",
            classifier_image_system_record: "",
            supporting_document_extraction_system_record: "",
            user_record0: "",
            admin_advice_intro: "",
            admin_advice_closing: "",
            created_at: Time.current,
            updated_at: Time.current
          )
      end

      def config_params
        attrs = {}
        %i[
          system_record
          classifier_system_record
          classifier_pdf_system_record
          classifier_image_system_record
          supporting_document_extraction_system_record
          user_record0
          admin_advice_intro
          admin_advice_closing
        ].each { |key| attrs[key] = params[key] if params.key?(key) }
        attrs
      end

      def serialize_config(config)
        {
          id: config.id,
          system_record: config.system_record,
          classifier_system_record: config.classifier_system_record,
          classifier_pdf_system_record:
            (
              if config.respond_to?(:classifier_pdf_system_record)
                config.classifier_pdf_system_record
              end
            ),
          classifier_image_system_record:
            (
              if config.respond_to?(:classifier_image_system_record)
                config.classifier_image_system_record
              end
            ),
          supporting_document_extraction_system_record:
            config.supporting_document_extraction_system_record,
          user_record0: config.user_record0,
          admin_advice_intro: config.admin_advice_intro,
          admin_advice_closing: config.admin_advice_closing,
          created_at: config.created_at,
          updated_at: config.updated_at
        }
      end
    end
  end
end
