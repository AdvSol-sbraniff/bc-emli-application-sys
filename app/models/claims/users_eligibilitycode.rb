# frozen_string_literal: true

# app/models/claims/users_eligibilitycode.rb
#
# Backed by: claims.users_eligibilitycodes
#
module Claims
  class UsersEligibilitycode < ApplicationRecord
    self.table_name = "claims.users_eligibilitycodes"

    belongs_to :user, class_name: "::User", foreign_key: :user_id

    validates :eligibility_code, presence: true, uniqueness: true
    validates :applied_at, :approved_at, :expires_at, presence: true

    # Optional: defensive check (mirrors DB constraint intent)
    validate :expires_after_applied

    private

    def expires_after_applied
      return if applied_at.blank? || expires_at.blank?
      errors.add(:expires_at, "must be after applied_at") if expires_at <= applied_at
    end
  end
end