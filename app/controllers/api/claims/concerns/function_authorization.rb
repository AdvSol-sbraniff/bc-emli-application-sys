# frozen_string_literal: true

module Api
  module Claims
    module Concerns
      module FunctionAuthorization
        extend ActiveSupport::Concern

        private

        def require_claims_function!(function_key)
          return if claims_function_keys.include?(function_key.to_s)

          render json: {
                   error: "Claims function access required.",
                   required_function: function_key
                 },
                 status: :forbidden
        end

        def claims_function_keys
          @claims_function_keys ||=
            ::Claims::Rbac.function_keys_for(current_user)
        end
      end
    end
  end
end
