# frozen_string_literal: true

module Api
  module Claims
    module Concerns
      module AdminAuthorization
        extend ActiveSupport::Concern
        include Api::Claims::Concerns::FunctionAuthorization

        included do
          class_attribute :required_claims_function_key,
                          instance_writer: false,
                          default: "claims.operations"
          before_action :require_claims_admin!
        end

        class_methods do
          def claims_function(function_key)
            self.required_claims_function_key = function_key.to_s
          end
        end

        private

        def require_claims_admin!
          require_claims_function!(required_claims_function_key)
        end
      end
    end
  end
end
