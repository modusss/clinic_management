module ClinicManagement
  module MessagesHelper

    def get_lead_messages(lead, appointment)
      LeadMessage.includes(:service_type).group_by { |m| m.service_type&.name || 'Sem categoria' }
    end

  end
end
