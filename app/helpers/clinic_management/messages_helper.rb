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

  end
end
