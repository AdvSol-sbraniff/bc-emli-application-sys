require "rails_helper"

RSpec.describe "Claims RBAC", type: :request do
  before { host! "localhost" }

  def authenticate_as(user)
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
    allow_any_instance_of(Api::Claims::RbacController).to receive(
      :current_user
    ).and_return(user)
  end

  it "returns the signed-in user's effective Claims functions" do
    authenticate_as(create(:user, role: :admin_manager))

    get "/api/claims/access"

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("function_keys")).to eq(
      %w[claims.configuration claims.operations]
    )
  end

  it "allows only a user with claims.role_functions to read the matrix" do
    authenticate_as(create(:user, role: :admin))
    get "/api/claims/admin/rbac"
    expect(response).to have_http_status(:forbidden)

    authenticate_as(create(:user, role: :system_admin))
    get "/api/claims/admin/rbac"

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("functions").length).to eq(6)
    expect(
      json_response.fetch("roles").map { |row| row.fetch("role_key") }
    ).to eq(%w[contractor admin admin_manager system_admin])
  end

  it "saves a complete matrix and returns inherited staff access" do
    authenticate_as(create(:user, role: :system_admin))
    assignments =
      Claims::Rbac
        .matrix
        .fetch(:functions)
        .map do |row|
          role_keys = row.fetch(:direct_role_keys)
          role_keys = ["admin_manager"] if row.fetch(:function_key) ==
            "claims.test_tools"
          { function_key: row.fetch(:function_key), role_keys: role_keys }
        end

    put "/api/claims/admin/rbac",
        params: {
          assignments: assignments
        },
        as: :json

    expect(response).to have_http_status(:ok)
    test_tools =
      json_response
        .fetch("functions")
        .find { |row| row.fetch("function_key") == "claims.test_tools" }
    expect(test_tools.fetch("direct_role_keys")).to eq(["admin_manager"])
    expect(test_tools.fetch("effective_role_keys")).to eq(
      %w[admin_manager system_admin]
    )
  end
end
