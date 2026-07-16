module ClinicManagement
  module MessagesHelper

    def get_lead_messages(lead, appointment)
      # Only show messages for the current referral if user is a referral, otherwise show global messages
      if referral?(current_user)
        # Referrals: agrupar apenas por service_type
        LeadMessage.includes(:service_type)
          .joins(:service_type)
          .where(referral_id: user_referral.id)
          .where(clinic_management_service_types: { removed: false })
          .group_by { |m| m.service_type&.name || 'Sem categoria' }
      else
        # Não-referrals: agrupar por tipo (Personalizadas vs Globais) e depois por service_type
        messages = LeadMessage.includes(:service_type)
          .joins(:service_type)
          .where(referral_id: nil)
          .where(clinic_management_service_types: { removed: false })
        
        # Separar mensagens personalizadas das globais
        personalizadas = messages.select { |m| m.message_type == 'outro' }
        globais = messages.select { |m| m.message_type != 'outro' }
        
        result = {}
        
        # Adicionar mensagens personalizadas
        if personalizadas.any?
          personalizadas_por_tipo = personalizadas.group_by { |m| m.service_type&.name || 'Sem categoria' }
          personalizadas_por_tipo.each do |service_name, msgs|
            result["📝 Personalizadas - #{service_name}"] = msgs
          end
        end
        
        # Adicionar mensagens globais
        if globais.any?
          globais_por_tipo = globais.group_by { |m| m.service_type&.name || 'Sem categoria' }
          globais_por_tipo.each do |service_name, msgs|
            result["🌐 Mensagens Globais - #{service_name}"] = msgs
          end
        end
        
        result
      end
    end

    # ESSENTIAL: Single efficient query - O(1) instead of loading ALL appointments.
    # Previous implementation loaded every appointment into memory (very slow with many records).
    # skip_query: true => return fallback immediately (for new form, no DB hit).
    def get_sample_appointment_for_preview(skip_query: false)
      return build_sample_appointment_fallback if skip_query

      apt = ClinicManagement::Appointment
        .joins(:invitation, :service, :lead)
        .where("clinic_management_invitations.patient_name IS NOT NULL AND clinic_management_invitations.patient_name != ''")
        .where("clinic_management_leads.name IS NOT NULL AND clinic_management_leads.name != ''")
        .where("clinic_management_services.date IS NOT NULL")
        .includes(invitation: :lead, service: :service_type)
        .order(Arel.sql("RANDOM()"))
        .limit(1)
        .first

      return apt if apt

      build_sample_appointment_fallback
    end

    def build_sample_appointment_fallback
      scheduled_start = Time.parse("14:20")
      scheduled_end = Time.parse("14:40")

      OpenStruct.new(
        invitation: OpenStruct.new(
          patient_name: "João Silva Santos",
          lead: OpenStruct.new(name: "João Silva Santos")
        ),
        service: OpenStruct.new(
          date: Date.current + 3.days,
          start_time: Time.parse("14:00"),
          end_time: Time.parse("17:30")
        ),
        effective_start_time: scheduled_start,
        effective_end_time: scheduled_end
      )
    end

    def format_placeholder_preview(text, appointment)
      return text unless appointment

      lead_name = appointment.invitation&.lead&.name || appointment.invitation&.patient_name || "Nome do Paciente"
      first_name = lead_name.split.first || "Primeiro"
      service_date = appointment.service&.date || Date.current
      time_variables = AppointmentMessageTimeResolver.resolve(appointment)

      # Format date components
      weekday = I18n.l(service_date, format: '%A').capitalize
      formatted_date = service_date.strftime('%d/%m/%y')
      month_name = I18n.l(service_date, format: '%B').capitalize
      day_number = service_date.strftime('%d')
      # Generate sample self-booking link for preview (only when account has self_booking_enabled)
      sample_booking_link = (defined?(current_account) && current_account&.self_booking_enabled?) ? generate_sample_self_booking_link(appointment) : ""

      # Replace placeholders
      result = text.gsub('{NOME_COMPLETO_PACIENTE}', lead_name)
                   .gsub('{PRIMEIRO_NOME_PACIENTE}', first_name)
                   .gsub('{DIA_SEMANA_ATENDIMENTO}', weekday)
                   .gsub('{DATA_DO_ATENDIMENTO}', formatted_date)
                   .gsub('{MES_DO_ATENDIMENTO}', month_name)
                   .gsub('{DIA_ATENDIMENTO_NUMERO}', day_number)
                   .gsub('{LINK_AUTO_MARCACAO}', sample_booking_link)

      time_variables.each do |placeholder, value|
        result = result.gsub("{#{placeholder}}", value)
      end

      result
    end

    # ============================================================================
    # Generate Sample Self-Booking Link for Preview
    # 
    # Creates a sample URL for the message preview. Uses actual lead data if available,
    # otherwise generates a placeholder URL.
    # 
    # ESSENTIAL: For preview purposes, we show both:
    # 1. ref (referral attribution) - if lead has attributed referral (180-day grace period)
    # 2. reg_by (registered by) - if there's a current_user logged in
    # 
    # This helps users understand how the final link will look with all parameters.
    # 
    # @param appointment [Appointment] The appointment to get lead from
    # @return [String] Sample URL for preview
    # ============================================================================
    def generate_sample_self_booking_link(appointment)
      lead = appointment&.invitation&.lead
      # Use :: prefix to access the main app's ApplicationController, not the engine's
      base_url = ::ApplicationController.app_url.chomp('/')
      
      if lead.present? && lead.respond_to?(:self_booking_token!)
        begin
          token = lead.self_booking_token!
          
          # Build URL parameters for preview
          url_params = []
          
          # 1. Check if lead has an attributed referral (within 180-day grace period)
          attributed_referral = lead.respond_to?(:current_attributed_referral) ? lead.current_attributed_referral : nil
          url_params << "ref=#{attributed_referral.id}" if attributed_referral.present?
          
          # 2. Include reg_by if there's a current user (shows who shared the link)
          if defined?(current_user) && current_user.present?
            url_params << "reg_by=#{current_user.id}"
          end
          
          # Build final URL
          if url_params.any?
            "#{base_url}/clinic_management/self_booking/#{token}?#{url_params.join('&')}"
          else
            "#{base_url}/clinic_management/self_booking/#{token}"
          end
        rescue => e
          # Fallback if token generation fails
          "#{base_url}/clinic_management/self_booking/EXEMPLO_TOKEN"
        end
      else
        # Fallback for sample data without real lead
        "#{base_url}/clinic_management/self_booking/EXEMPLO_TOKEN"
      end
    end

    # Check if Evolution API can be used based on user type and instance connection status
    # Supports multiple instances for referrals (new system)
    def can_use_evolution_api?
      if Rails.env.development?
        return true
      end
      if referral?(current_user)
        # For referral users, check if they have any connected instance
        # Uses new has_connected_instances? method that supports multiple instances
        referral = user_referral
        referral&.has_connected_instances? == true
      else
        # For non-referral users, always prefer tenant-aware account context.
        # ESSENTIAL: using Account.first may read another tenant's connection flag
        # and incorrectly block Evolution API checks in clinic absent flow.
        account = if defined?(current_account) && current_account.present?
          current_account
        else
          Account.first
        end

        account&.instance_2_connected == true
      end
    end

    # Generate a specific variation of a message with random options
    def generate_random_variation(text, appointment, seed)
      # First replace placeholders with patient data
      processed_text = format_placeholder_preview(text, appointment)
      
      # Then process random options [option1|option2|option3]
      processed_text.gsub(/\[([^\]]+)\]/) do |match|
        options = $1.split('|').map(&:strip)
        # Use seed to ensure different variations
        index = (seed.to_f * options.length).floor % options.length
        options[index]
      end
    end

    # Meta bulk send on clinic absent patients screen (staff only).
    # ESSENTIAL: Uses meta_bulk_absent_allowed_roles — NOT meta_whatsapp_role_allowed? (campaigns separate).
    #
    # @return [Boolean]
    def can_use_meta_bulk_for_absent?
      return false unless defined?(current_account) && current_account.present?
      return false if referral?(current_user)
      return false unless current_account.meta_whatsapp_enabled?
      return false unless meta_bulk_absent_role_allowed?
      return false unless meta_bulk_account_operational?

      default_meta_phone_for_bulk&.can_send_message?
    rescue StandardError => e
      Rails.logger.warn("[MessagesHelper] can_use_meta_bulk_for_absent? failed: #{e.class}: #{e.message}")
      false
    end

    # Approved Meta templates linked to global LeadMessages (staff absent bulk).
    #
    # @return [Array<Hash>] :template, :lead_message, :had_variation_blocks
    def absent_meta_bulk_templates
      return [] unless defined?(current_account) && current_account.present?
      return [] unless can_use_meta_bulk_for_absent?
      return [] unless MetaTemplate.respond_to?(:from_lead_message)

      waba_ids = current_account.meta_business_accounts.active.pluck(:id)
      templates = MetaTemplate
                    .where(meta_business_account_id: waba_ids)
                    .from_lead_message
                    .approved
                    .current_versions
      templates = templates.campaign_sendable if MetaTemplate.respond_to?(:campaign_sendable)
      templates = templates.includes(:meta_business_account)

      lead_message_ids = templates.map(&:source_id).compact
      lead_messages = ClinicManagement::LeadMessage.where(id: lead_message_ids, referral_id: nil).index_by(&:id)

      templates.filter_map do |template|
        lead_message = lead_messages[template.source_id]
        next unless lead_message

        { template: template, lead_message: lead_message, had_variation_blocks: template.try(:had_variation_blocks?) }
      end.sort_by { |row| row[:lead_message].name.to_s.downcase }
    end

    # Readiness summary for Meta bulk panel on absent screen.
    #
    # @return [Hash]
    def absent_meta_readiness
      phone = default_meta_phone_for_bulk
      templates = absent_meta_bulk_templates

      {
        ready: can_use_meta_bulk_for_absent? && templates.any? && phone&.can_send_message?,
        phone_display: phone&.display_phone,
        templates_count: templates.size,
        meta_config_path: "/admin/accounts/#{current_account&.id}/meta_whatsapp"
      }
    end

    private

    # @return [Boolean]
    def meta_bulk_absent_role_allowed?
      return false unless current_user.present?

      role = current_user.memberships.order(:id).first&.role
      return false unless current_account.respond_to?(:meta_bulk_absent_role_allowed?)

      current_account.meta_bulk_absent_role_allowed?(role)
    end

    # @return [Boolean]
    def meta_bulk_account_operational?
      return false unless current_account.respond_to?(:meta_inbox_operational?)

      current_account.meta_inbox_operational?
    end

    # Resolves default Meta phone with fallback when host Account lacks the helper method.
    #
    # @return [MetaPhoneNumber, nil]
    def default_meta_phone_for_bulk
      account = current_account
      return nil unless account

      if account.respond_to?(:default_meta_phone_number)
        account.default_meta_phone_number
      else
        MetaPhoneNumber
          .joins(:meta_business_account)
          .merge(MetaBusinessAccount.active.where(account_id: account.id))
          .active
          .find { |phone| phone.has_access_token? }
      end
    end

  end
end
