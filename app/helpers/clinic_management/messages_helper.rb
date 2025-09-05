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

    def get_sample_appointment_for_preview
      # Try to get a random appointment with complete data for preview
      appointments = ClinicManagement::Appointment.includes(invitation: :lead, service: :service_type).all
      
      # Filter appointments with complete data
      valid_appointments = appointments.select do |apt|
        apt.invitation&.patient_name.present? &&
        apt.invitation&.lead&.name.present? &&
        apt.service&.date.present?
      end
      
      # Return a random valid appointment
      return valid_appointments.sample if valid_appointments.any?

      # Fallback: create sample data if no real appointments exist
      OpenStruct.new(
        invitation: OpenStruct.new(
          patient_name: "João Silva Santos",
          lead: OpenStruct.new(name: "João Silva Santos")
        ),
        service: OpenStruct.new(
          date: Date.current + 3.days,
          start_time: Time.parse("14:00"),
          end_time: Time.parse("17:30")
        )
      )
    end

    def format_placeholder_preview(text, appointment)
      return text unless appointment

      lead_name = appointment.invitation&.lead&.name || appointment.invitation&.patient_name || "Nome do Paciente"
      first_name = lead_name.split.first || "Primeiro"
      service_date = appointment.service&.date || Date.current
      start_time = appointment.service&.start_time || Time.parse("14:00")
      end_time = appointment.service&.end_time || Time.parse("17:30")

      # Format date components
      weekday = I18n.l(service_date, format: '%A').capitalize
      formatted_date = service_date.strftime('%d/%m/%y')
      month_name = I18n.l(service_date, format: '%B').capitalize
      day_number = service_date.strftime('%d')
      start_hour = start_time.strftime('%H:%M')
      end_hour = end_time.strftime('%H:%M')

      # Replace placeholders
      text.gsub('{NOME_COMPLETO_PACIENTE}', lead_name)
          .gsub('{PRIMEIRO_NOME_PACIENTE}', first_name)
          .gsub('{DIA_SEMANA_ATENDIMENTO}', weekday)
          .gsub('{DATA_DO_ATENDIMENTO}', formatted_date)
          .gsub('{MES_DO_ATENDIMENTO}', month_name)
          .gsub('{DIA_ATENDIMENTO_NUMERO}', day_number)
          .gsub('{HORARIO_DE_INICIO}', start_hour)
          .gsub('{HORARIO_DE_TERMINO}', end_hour)
    end

    # Check if Evolution API can be used based on user type and instance connection status
    def can_use_evolution_api?
      #return false unless message_id.present?
      if referral?(current_user)
        # For referral users, check if their instance is connected
        referral = user_referral
        referral&.instance_connected == true
      else
        # For non-referral users, check if instance 2 is connected
        Account.first.instance_2_connected == true
      end
    end

  end
end
