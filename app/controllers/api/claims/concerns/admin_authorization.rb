# frozen_string_literal: true

module Api
  module Claims
    module Concerns
      module AdminAuthorization
        extend ActiveSupport::Concern

        included { before_action :require_claims_admin! }

        private

        def require_claims_admin!
          if current_user&.admin? || current_user&.admin_manager? ||
               current_user&.system_admin?
            return
          end

          render json: {
                   error: "Claims admin access required."
                 },
                 status: :forbidden
        end
      end
    end
  end
end
