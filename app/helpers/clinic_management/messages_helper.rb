module ClinicManagement
  module MessagesHelper

    def get_lead_messages(lead, appointment)
      # Only show messages for the current referral if user is a referral, otherwise show global messages
      if referral?(current_user)
        LeadMessage.includes(:service_type)
          .where(referral_id: user_referral.id)
          .group_by { |m| m.service_type&.name || 'Sem categoria' }
      else
        LeadMessage.includes(:service_type)
          .where(referral_id: nil)
          .group_by { |m| m.service_type&.name || 'Sem categoria' }
      end
    end

    # Check if Evolution API can be used based on user type and instance connection status
    def can_use_evolution_api?(message_id = nil)
      return false unless message_id.present?
      
      if referral?(current_user)
        # For referral users, check if their instance is connected
        referral = user_referral
        referral&.instance_connected == true
      else
        # For non-referral users, check if instance 2 is connected
        membership = current_user.memberships.last
        membership&.instance_2_connected == true
      end
    end

  end
end
