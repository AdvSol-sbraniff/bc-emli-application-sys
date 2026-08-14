require "rails_helper"

RSpec.describe Claims::Rbac do
  let(:contractor) { create(:user, role: :contractor) }
  let(:admin) { create(:user, role: :admin) }
  let(:admin_manager) { create(:user, role: :admin_manager) }
  let(:system_admin) { create(:user, role: :system_admin) }

  describe ".function_keys_for" do
    it "applies the configured direct roles and staff inheritance" do
      expect(described_class.function_keys_for(contractor)).to eq(
        ["claims.contractor_portal"]
      )
      expect(described_class.function_keys_for(admin)).to eq(
        ["claims.operations"]
      )
      expect(described_class.function_keys_for(admin_manager)).to eq(
        %w[claims.configuration claims.operations]
      )
      expect(described_class.function_keys_for(system_admin)).to eq(
        %w[
          claims.configuration
          claims.hard_delete
          claims.operations
          claims.role_functions
          claims.test_tools
        ]
      )
    end
  end

  describe ".replace_assignments!" do
    it "rejects removal of the protected RBAC administration assignment" do
      assignments =
        described_class
          .matrix
          .fetch(:functions)
          .map do |row|
            {
              function_key: row.fetch(:function_key),
              role_keys:
                if row.fetch(:function_key) == "claims.role_functions"
                  []
                else
                  row.fetch(:direct_role_keys)
                end
            }
          end

      expect do
        described_class.replace_assignments!(
          assignments: assignments,
          actor: system_admin
        )
      end.to raise_error(
        ArgumentError,
        "claims.role_functions must remain assigned only to system_admin."
      )
    end
  end
end
