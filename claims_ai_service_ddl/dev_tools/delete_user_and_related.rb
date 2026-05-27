# Rerunnable local reset helper for a user and their related records.
#
# Usage from the app container or local app shell:
#   USER_IDENTIFIER=MiniMe1 bundle exec rails runner /app/claims_ai_service_ddl/delete_user_and_related.rb
#   USER_IDENTIFIER=minime1@gmail.com bundle exec rails runner /app/claims_ai_service_ddl/delete_user_and_related.rb
#   USER_IDENTIFIER=<user-uuid> bundle exec rails runner /app/claims_ai_service_ddl/delete_user_and_related.rb
#
# The identifier is resolved in this order:
# - exact UUID id
# - exact email (case-insensitive)
# - exact omniauth_username (case-insensitive)
# - exact first_name (case-insensitive, only if unique)

identifier = ENV["USER_IDENTIFIER"].to_s.strip
raise "USER_IDENTIFIER is required" if identifier.blank?

def resolve_user(identifier)
  user = User.find_by(id: identifier)
  return user if user.present?

  user = User.where("lower(email) = ?", identifier.downcase).first
  return user if user.present?

  user = User.where("lower(omniauth_username) = ?", identifier.downcase).first
  return user if user.present?

  first_name_matches =
    User.where("lower(first_name) = ?", identifier.downcase).to_a
  return first_name_matches.first if first_name_matches.one?
  return nil if first_name_matches.empty?

  raise "Multiple users matched first_name=#{identifier.inspect}; use email, username, or id instead"
end

user = resolve_user(identifier)
raise "No user found for #{identifier.inspect}" if user.blank?

puts "Deleting user #{user.id} (email=#{user.email.inspect}, username=#{user.omniauth_username.inspect}, role=#{user.role})"

ApplicationRecord.transaction do
  # Nullify non-owned historical references first.
  User.where(invited_by_id: user.id, invited_by_type: "User").update_all(
    invited_by_id: nil,
    invited_by_type: nil
  )
  ContractorOnboard.where(suspended_by: user.id).update_all(suspended_by: nil)
  ContractorOnboard.where(deactivated_by: user.id).update_all(
    deactivated_by: nil
  )
  TemplateVersion.where(deprecated_by_id: user.id).update_all(
    deprecated_by_id: nil
  )
  RequirementTemplate.where(assignee_id: user.id).update_all(assignee_id: nil)
  ContractorImport.where(consumed_by_user_id: user.id).update_all(
    consumed_by_user_id: nil
  )

  # Direct user-linked records that are not fully covered by dependent callbacks.
  AllowlistedJwt.where(user_id: user.id).delete_all
  AuditLog.where(user_id: user.id).delete_all
  ApplicationAssignment.where(user_id: user.id).delete_all
  RevisionRequest.where(user_id: user.id).delete_all
  SupportRequest.where(requested_by_id: user.id).delete_all
  EarlyAccessPreview.where(previewer_id: user.id).delete_all
  JurisdictionMembership.where(user_id: user.id).delete_all

  # User as collaborator or collaboration owner.
  Collaborator.where(user_id: user.id).find_each(&:destroy)
  Collaborator.where(
    collaboratorable_type: "User",
    collaboratorable_id: user.id
  ).find_each(&:destroy)

  # User-scoped relations.
  UserLicenseAgreement.where(
    account_type: "User",
    account_id: user.id
  ).delete_all
  Contact.where(contactable_type: "User", contactable_id: user.id).delete_all
  UserAddress.where(user_id: user.id).delete_all
  ProgramMembership.where(user_id: user.id).find_each(&:destroy)
  ContractorEmployee.where(employee_id: user.id).delete_all

  # User-submitted permit applications.
  PermitApplication.where(
    submitter_type: "User",
    submitter_id: user.id
  ).find_each(&:destroy)

  # Contractor records where this user is the primary contact.
  Contractor
    .where(contact_id: user.id)
    .find_each do |contractor|
      puts "Deleting contractor #{contractor.id} for user #{user.id}"

      ContractorEmployee.where(contractor_id: contractor.id).delete_all
      ContractorImport.where(contractor_id: contractor.id).update_all(
        contractor_id: nil
      )
      ContractorOnboard.where(contractor_id: contractor.id).delete_all
      PermitApplication.where(
        submitter_type: "Contractor",
        submitter_id: contractor.id
      ).find_each(&:destroy)
      contractor.contractor_info&.destroy
      contractor.destroy!
    end

  user.preference&.destroy
  user.destroy!
end

begin
  User.reindex
  Contractor.reindex
  PermitApplication.reindex
rescue StandardError => e
  puts "Reindex warning: #{e.class}: #{e.message}"
end

puts "Deleted user #{user.id}"
