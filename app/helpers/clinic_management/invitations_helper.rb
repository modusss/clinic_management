module ClinicManagement
  module InvitationsHelper
    # Display name for indicator key (Referral or local user row).
    # Keys can be: Referral object, or { local_user: User } for "Vanessa (Local)" format.
    # @param key [Referral, Hash, nil] referral or { local_user: User }
    # @return [String] display name for the indicator column
    def indicator_display_name(key)
      return "Sem indicador" if key.nil?
      return "#{key[:local_user]&.name} (Local)" if key.is_a?(Hash) && key.key?(:local_user)
      key.respond_to?(:name) ? key.name : key.to_s
    end
  end
end
