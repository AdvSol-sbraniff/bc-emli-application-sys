# frozen_string_literal: true

# app/models/claims/users_eligibilitycode.rb
#
# Backed by: claims.users_eligibilitycodes
#
module Claims
  class UsersEligibilitycode < ApplicationRecord
    self.table_name = "claims.users_eligibilitycodes"

    belongs_to :user, class_name: "::User", foreign_key: :user_id

    before_validation :set_income_level_from_eligibility_code

    validates :eligibility_code, presence: true, uniqueness: true
    validates :income_level, presence: true, inclusion: { in: [1, 2, 3] }
    validates :applied_at, :approved_at, :expires_at, presence: true

    # Optional: defensive check (mirrors DB constraint intent)
    validate :eligibility_code_has_known_income_level
    validate :expires_after_applied

    def self.income_level_from_eligibility_code(value)
      token = value.to_s.strip.upcase
      return 1 if token.start_with?("ESP1") || token.start_with?("ESPI")
      return 2 if token.start_with?("ESP2")
      return 3 if token.start_with?("ESP3")

      nil
    end

    private

    def set_income_level_from_eligibility_code
      self.income_level =
        self.class.income_level_from_eligibility_code(eligibility_code)
    end

    def eligibility_code_has_known_income_level
      return if eligibility_code.blank? || income_level.present?

      errors.add(:eligibility_code, "must start with ESP1, ESPI, ESP2, or ESP3")
    end

    def expires_after_applied
      return if applied_at.blank? || expires_at.blank?
      if expires_at <= applied_at
        errors.add(:expires_at, "must be after applied_at")
      end
    end
  end
end
