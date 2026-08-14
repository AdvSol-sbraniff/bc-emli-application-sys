# frozen_string_literal: true

module Api
  module Claims
    class RbacController < Api::ApplicationController
      include Api::Claims::Concerns::FunctionAuthorization

      skip_after_action :verify_authorized, only: %i[access show update]
      before_action -> { require_claims_function!("claims.role_functions") },
                    only: %i[show update]

      def access
        render json: {
                 role_key: current_user.role,
                 function_keys: ::Claims::Rbac.function_keys_for(current_user)
               },
               status: :ok
      end

      def show
        render json: ::Claims::Rbac.matrix, status: :ok
      end

      def update
        matrix =
          ::Claims::Rbac.replace_assignments!(
            assignments: params.require(:assignments),
            actor: current_user
          )
        render json: matrix, status: :ok
      rescue ActionController::ParameterMissing, ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
