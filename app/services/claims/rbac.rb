# frozen_string_literal: true

module Claims
  module Rbac
    ROLE_KEYS = %w[contractor admin admin_manager system_admin].freeze
    STAFF_ROLE_INHERITANCE = {
      "admin" => %w[admin],
      "admin_manager" => %w[admin admin_manager],
      "system_admin" => %w[admin admin_manager system_admin]
    }.freeze
    PROTECTED_ASSIGNMENTS = {
      "claims.role_functions" => %w[system_admin]
    }.freeze

    module_function

    def function_keys_for(user)
      role_keys = effective_role_keys(user&.role)
      return [] if role_keys.empty?

      ::Claims::Function
        .joins(:role_functions)
        .where("claims.role_functions.role_key IN (?)", role_keys)
        .distinct
        .order(:function_key)
        .pluck(:function_key)
    end

    def allowed?(user, function_key)
      function_keys_for(user).include?(function_key.to_s)
    end

    def matrix
      direct_roles_by_function =
        ::Claims::RoleFunction
          .joins(:function)
          .order(:role_key)
          .pluck("claims.functions.function_key", :role_key)
          .each_with_object(
            Hash.new { |hash, key| hash[key] = [] }
          ) do |(function_key, role_key), grouped|
            grouped[function_key] << role_key
          end

      {
        roles: ROLE_KEYS.map { |role_key| { role_key: role_key } },
        functions:
          ::Claims::Function
            .order(:function_key)
            .map do |function_row|
              direct_role_keys =
                direct_roles_by_function[function_row.function_key]
              {
                id: function_row.id,
                function_key: function_row.function_key,
                description: function_row.description,
                direct_role_keys: direct_role_keys,
                effective_role_keys:
                  ROLE_KEYS.select do |role_key|
                    effective_role_keys(role_key).any? do |inherited_role|
                      direct_role_keys.include?(inherited_role)
                    end
                  end
              }
            end
      }
    end

    def replace_assignments!(assignments:, actor:)
      normalized = normalize_assignments(assignments)
      before =
        ::Claims::RoleFunction
          .joins(:function)
          .pluck("claims.functions.function_key", :role_key)
          .sort

      ::Claims::RoleFunction.transaction do
        ::Claims::RoleFunction.delete_all
        normalized.each do |function_key, role_keys|
          function_row = ::Claims::Function.find_by!(function_key: function_key)
          role_keys.each do |role_key|
            ::Claims::RoleFunction.create!(
              function: function_row,
              role_key: role_key
            )
          end
        end
      end

      after =
        normalized
          .flat_map do |function_key, role_keys|
            role_keys.map { |role_key| [function_key, role_key] }
          end
          .sort
      Rails.logger.info(
        "[CLAIMS][RBAC] assignments_updated actor_user_id=#{actor&.id} actor_role=#{actor&.role} " \
          "before=#{before.inspect} after=#{after.inspect}"
      )
      matrix
    end

    def effective_role_keys(role_key)
      normalized_role = role_key.to_s
      return ["contractor"] if normalized_role == "contractor"

      STAFF_ROLE_INHERITANCE.fetch(normalized_role, [])
    end

    def normalize_assignments(assignments)
      rows = Array(assignments)
      supplied_keys = rows.map { |row| value_for(row, :function_key).to_s }.sort
      known_keys = ::Claims::Function.order(:function_key).pluck(:function_key)
      unless supplied_keys == known_keys
        raise ArgumentError,
              "Assignments must include every configured function exactly once."
      end

      rows.each_with_object({}) do |row, normalized|
        function_key = value_for(row, :function_key).to_s
        role_keys = Array(value_for(row, :role_keys)).map(&:to_s).uniq
        unknown_roles = role_keys - ROLE_KEYS
        if unknown_roles.any?
          raise ArgumentError, "Unknown role: #{unknown_roles.first}"
        end

        protected_roles = PROTECTED_ASSIGNMENTS[function_key]
        if protected_roles && role_keys.sort != protected_roles.sort
          raise ArgumentError,
                "#{function_key} must remain assigned only to system_admin."
        end

        normalized[function_key] = remove_redundant_staff_assignments(role_keys)
      end
    end
    private_class_method :normalize_assignments

    def remove_redundant_staff_assignments(role_keys)
      normalized = role_keys.dup
      if normalized.include?("admin")
        normalized -= %w[admin_manager system_admin]
      elsif normalized.include?("admin_manager")
        normalized -= %w[system_admin]
      end
      normalized.sort
    end
    private_class_method :remove_redundant_staff_assignments

    def value_for(row, key)
      return row[key] if row.respond_to?(:key?) && row.key?(key)
      return row[key.to_s] if row.respond_to?(:key?) && row.key?(key.to_s)

      nil
    end
    private_class_method :value_for
  end
end
