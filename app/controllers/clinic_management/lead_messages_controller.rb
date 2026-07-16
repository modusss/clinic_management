module ClinicManagement
  class LeadMessagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_message, only: [:show, :edit, :update, :destroy]
    before_action :check_message_permissions, only: [:edit, :update, :destroy]
    skip_before_action :redirect_referral_users
    include GeneralHelper
    include MessagesHelper
    require 'httparty'

    # ESSENTIAL: Order by created_at ASC so numbering (#1, #2, #3)
    # matches the send order in jobs.
    #
    # For managers: loads @referrals_with_messages (referrals that have at least
    # one lead_message) and allows filtering via params[:referral_id].
    # @viewing_referral is set when a manager selects a specific referral.
    #
    # When multi_service_locations_enabled: location filter via params[:service_location_id].
    # "" = Interno (service_location_id nil); "all" = all externals; id = specific location.
    def index
      if referral?(current_user)
        # Referral users: see only their own messages (unchanged)
        @messages = LeadMessage.where(referral_id: user_referral.id).order(created_at: :asc)
      elsif can_manage_lead_messages?
        # Operator, manager, owner: global messages OR a specific referral's messages
        # Only show active referrals in the dropdown.
        # Uses the instance method active? (same approach as referrals#index)
        # because the scope Referral.active has a LEFT JOIN bug that leaks
        # referrals without memberships.
        referral_ids = LeadMessage.where.not(referral_id: nil).distinct.pluck(:referral_id)
        @referrals_with_messages = Referral.where(id: referral_ids)
                                           .order(:name)
                                           .select(&:active?)

        if params[:referral_id].present?
          @viewing_referral = Referral.find_by(id: params[:referral_id])
          @messages = LeadMessage.where(referral_id: params[:referral_id]).order(created_at: :asc)
        else
          @viewing_referral = nil
          @messages = LeadMessage.where(referral_id: nil).order(created_at: :asc)
        end
      else
        # Non-manager, non-referral: global messages only (unchanged)
        @messages = LeadMessage.where(referral_id: nil).order(created_at: :asc)
      end

      # ESSENTIAL: When multi-regions disabled, show ONLY interno/global messages (service_location_id nil).
      # Messages assigned to external locations remain in DB but are hidden until multi-regions is re-enabled.
      unless multi_service_locations_enabled?
        @messages = @messages.where(service_location_id: nil)
      end

      # Filter by service_location from navbar when multi-regions enabled (no page selector).
      @viewing_all_externals = false
      if multi_service_locations_enabled? && @viewing_referral.nil? && !referral?(current_user)
        loc_id = current_service_location_id.to_s
        @messages = filter_messages_by_location(@messages, loc_id)
        # When "Todos externos": group by location for segmented display.
        # Each section shows location name + its messages (including empty locations).
        if loc_id == "all"
          @viewing_all_externals = true
          @messages_by_location = ServiceLocation.order(:name).map { |loc|
            [loc, @messages.select { |m| m.service_location_id == loc.id }]
          }
        end
      end

      @messages_by_type = @messages.group_by(&:message_type)

      load_automation_index_state if show_automation_channel_ui?
      @show_automation_channel_ui ||= false
      @automation_tab ||= "evolution"
    end
  
    def new
      @message = LeadMessage.new
    end
  
    def create
      attrs = message_params.to_h
      # ESSENTIAL: Normalize service_location_id - "internal" -> nil
      if attrs.key?(:service_location_id)
        attrs[:service_location_id] = normalize_service_location_param(attrs[:service_location_id])
      end

      # ESSENTIAL: When navbar is "Todos" and multi enabled, require location selection
      if require_service_location_selection? && attrs[:service_location_id].blank?
        @message = LeadMessage.new(attrs)
        @message.errors.add(:service_location_id, "deve ser selecionado quando 'Todos externos' está ativo")
        render :new and return
      end

      @message = LeadMessage.new(attrs)
      # If the user is a referral, associate the message with their referral_id
      @message.referral_id = user_referral.id if referral?(current_user)
      
      # Force message_type = 3 (outro) for referrals and non-manager users
      if referral?(current_user)
        @message.message_type = 3
      elsif !can_manage_lead_messages?
        @message.message_type = 3
      end
      
      # Auto-assign service_type if there's only one available and none selected
      if @message.service_type_id.blank?
        service_types = ServiceType.where(removed: false)
        @message.service_type_id = service_types.first.id if service_types.count == 1
      end

      if @message.save
        redirect_to lead_messages_path, notice: "Mensagem customizada criada com sucesso."
      else
        # Log validation errors for debugging
        Rails.logger.error "LeadMessage validation errors: #{@message.errors.full_messages.join(', ')}"
        render :new
      end
    end
  
    def show
    end
  
    def edit
    end
  
    def update
      attrs = message_params.to_h
      # ESSENTIAL: Normalize service_location_id - "internal" -> nil
      if attrs.key?(:service_location_id)
        attrs[:service_location_id] = normalize_service_location_param(attrs[:service_location_id])
      end

      if @message.update(attrs)
        # Force message_type = 3 (outro) for referrals and non-manager users
        if referral?(current_user)
          @message.message_type = 3
        elsif !can_manage_lead_messages?
          @message.message_type = 3
        end
        
        # Auto-assign service_type if there's only one available and none selected
        if @message.service_type_id.blank?
          service_types = ServiceType.where(removed: false)
          @message.service_type_id = service_types.first.id if service_types.count == 1
        end
        
        @message.save if @message.changed?

        notice = "Mensagem customizada atualizada com sucesso."

        # Preserve referral context when redirecting back (location comes from navbar)
        redirect_path = @message.referral_id.present? ?
          lead_messages_path(referral_id: @message.referral_id) : lead_messages_path
        redirect_to redirect_path, notice: notice
      else
        render :edit
      end
    end

    def destroy
      referral_id = @message.referral_id
      @message.destroy

      # Preserve referral context when redirecting back (location comes from navbar)
      redirect_path = referral_id.present? ?
        lead_messages_path(referral_id: referral_id) : lead_messages_path
      redirect_to redirect_path, notice: 'Mensagem customizada excluída com sucesso.'
    end

    # PATCH collection — toggle account-wide clinic automation channel.
    def update_automation_channel
      unless can_manage_lead_messages?
        redirect_to lead_messages_path, alert: "Sem permissão."
        return
      end

      channel = params[:clinic_automation_channel].to_s
      unless Account::CLINIC_AUTOMATION_CHANNELS.include?(channel)
        redirect_to lead_messages_path, alert: "Canal inválido."
        return
      end

      if channel == "meta" && !current_account.clinic_automation_meta_available?
        redirect_to lead_messages_path, alert: "WhatsApp Meta não está operacional."
        return
      end

      current_account.update!(clinic_automation_channel: channel)
      redirect_to lead_messages_path(tab: params[:tab].presence || "meta"),
                  notice: channel == "meta" ? "Automações clínicas usarão WhatsApp Meta." : "Automações clínicas usarão WhatsApp próprio (Evolution)."
    end

    # PATCH collection — enable/disable a Meta template in clinic automation for a service location.
    def toggle_meta_template_automation
      unless can_manage_lead_messages?
        redirect_to lead_messages_path, alert: "Sem permissão."
        return
      end

      template = MetaTemplate.find_by(id: params[:meta_template_id])
      unless template
        redirect_to lead_messages_path(tab: "meta"), alert: "Template não encontrado."
        return
      end

      service_location_id = normalize_meta_automation_service_location_id(params[:service_location_id])
      enabled = params[:enabled].to_s == "1"

      ClinicMetaAutomationPreference.upsert_enabled!(
        template: template,
        service_location_id: service_location_id,
        enabled: enabled
      )

      state = enabled ? "ativado" : "desativado"
      location_name = meta_automation_location_label(service_location_id)
      redirect_to lead_messages_path(tab: "meta"),
                  notice: "Template '#{template.root_template.name}' #{state} na automação Meta (#{location_name})."
    end

    # PATCH member — assign Meta template to a LeadMessage slot (legacy — UI removed).
    def meta_assignment
      unless can_manage_lead_messages?
        redirect_to lead_messages_path, alert: "Sem permissão."
        return
      end

      @message = LeadMessage.find(params[:id])
      attrs = {
        meta_template_id: params[:meta_template_id].presence,
        delivery_channel: params[:delivery_channel].presence
      }

      if @message.update(attrs)
        redirect_to lead_messages_path(tab: "meta"), notice: "Template Meta vinculado a '#{@message.name}'."
      else
        redirect_to lead_messages_path(tab: "meta"), alert: @message.errors.full_messages.to_sentence
      end
    end

    # GET collection — JSON options for Meta template picker.
    def meta_template_options
      unless can_manage_lead_messages?
        render json: { templates: [] }, status: :forbidden
        return
      end

      message_type = params[:message_type].to_s
      templates = meta_templates_for_slot(message_type).map do |t|
        {
          id: t.id,
          name: t.name,
          status: t.status,
          body_preview: t.body_text.to_s.truncate(120),
          ready: t.clinic_automation_ready?
        }
      end

      render json: { templates: templates }
    end

    def build_message
      begin
        message = LeadMessage.find_by(id: params[:custom_message_id])
        appointment = Appointment.find_by(id: params[:appointment_id])
        # NOTE: add_message_sent was removed from here - it should only be called
        # when the message is actually SENT (via send_evolution_message or manual send)
        # not when the user just selects a message from the dropdown
        lead = Lead.find_by(id: params[:lead_id])
        message_data = get_message(message, lead, appointment.service)
        context = params[:context] || 'other'  # Capturar contexto
        
        # Check if we can use Evolution API for automatic sending (with error handling)
        can_use_evolution = false
        begin
          can_use_evolution = can_send_via_evolution?
        rescue => evolution_error
          Rails.logger.error "Error checking Evolution API availability: #{evolution_error.message}"
          can_use_evolution = false
        end
        
        # NOTE: We no longer update messages-sent here because the message
        # hasn't been sent yet - user just selected it from dropdown.
        # The messages-sent will be updated when user actually sends the message.
        render turbo_stream: turbo_stream.append(
          "whatsapp-link-#{lead.id}", 
          partial: "clinic_management/lead_messages/whatsapp_link", 
          locals: { 
            phone_number: lead.phone, 
            message: message_data[:text],
            media_details: message_data[:media],
            lead_id: lead.id,
            appointment_id: appointment.id,
            can_use_evolution: can_use_evolution,
            message_id: message.id,
            context: context  # Passar contexto para o partial
          }
        )        
      rescue => e
        Rails.logger.error "Error in build_message: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Always provide fallback manual option even on error
        lead = Lead.find_by(id: params[:lead_id])
        appointment = Appointment.find_by(id: params[:appointment_id])
        context = params[:context] || 'other'  # Capturar contexto mesmo no erro
        
        if lead && appointment
          # Try to get a basic message or use a fallback
          fallback_message = "Olá #{lead.name.split(' ').first}!"
          
          render turbo_stream: turbo_stream.append(
            "whatsapp-link-#{lead.id}", 
            partial: "clinic_management/lead_messages/whatsapp_link", 
            locals: { 
              phone_number: lead.phone, 
              message: fallback_message,
              lead_id: lead.id,
              appointment_id: appointment.id,
              can_use_evolution: false,
              message_id: nil,
              context: context  # Passar contexto para o partial
            }
          )
        else
          render turbo_stream: turbo_stream.replace(
            "whatsapp-link-#{params[:lead_id]}", 
            html: "<p>Erro ao gerar mensagem. Dados não encontrados.</p>"
          )
        end
      end
    end

    def send_evolution_message
      Rails.logger.info "🚀 send_evolution_message called with params: #{params.inspect}"
      
      begin
        message = LeadMessage.find_by(id: params[:message_id])
        appointment = Appointment.find_by(id: params[:appointment_id])
        lead = Lead.find_by(id: params[:lead_id])
        context = params[:context] || 'other'  # Capturar contexto
        
        Rails.logger.info "📋 Found records - Message: #{message&.id}, Appointment: #{appointment&.id}, Lead: #{lead&.id}, Context: #{context}"
        
        message_data = get_message(message, lead, appointment.service)
        message_text = message_data[:text]
        media_details = message_data[:media]
        
        # Remove URL encoding for Evolution API
        message_text = CGI.unescape(message_text)
        
        phone = lead.phone
        # Remove código do país se já tiver (será adicionado no job)
        phone = phone.sub(/^55/, '')
        
        # Determina qual instância usar
        instance_name = get_instance_name
        
        Rails.logger.info "🔍 Lead #{lead.id} (#{lead.name}) usando instância: #{instance_name}"
        
        # Validar se instance_name está presente
        if instance_name.blank?
          Rails.logger.error "❌ instance_name está vazio! Não é possível enviar mensagem."
          render json: {
            success: false,
            message: "Erro: Instância do WhatsApp não configurada. Por favor, configure a instância Evolution API.",
            lead_id: lead.id
          }
          return
        end
        
        # ⚠️ VALIDAÇÃO SÍNCRONA: Verificar se o número tem WhatsApp ANTES de enfileirar
        Rails.logger.info "🔍 Validando se número #{phone} tem WhatsApp..."
        
        # Usando endpoint de checkNumberStatus do Evolution API em vez de enviar mensagem
        # Se não tiver o helper específico, vamos assumir que o número é válido para evitar enviar "✓"
        # Se quiser manter a validação estrita, precisaria implementar o checkNumberStatus no helper
        
        # validation_response = send_api_zap_message("✓", phone, false, instance_name)
        
        # Por enquanto, vamos confiar que o número é válido e deixar o job lidar com erros de envio
        # Isso evita o envio da mensagem "✓" indesejada
        
        # Parsar resposta se for HTTParty::Response
        # parsed_validation = validation_response.is_a?(HTTParty::Response) ? validation_response.parsed_response : validation_response
        
        # Verificar se o número não tem WhatsApp
        # if parsed_validation.is_a?(Hash) && 
        #    parsed_validation["status"] == 400 && 
        #    parsed_validation.dig("response", "message")&.is_a?(Array) &&
        #    parsed_validation.dig("response", "message")&.any? { |msg| msg.is_a?(Hash) && msg["exists"] == false }
          
        #   Rails.logger.warn "⚠️ Número #{phone} não tem WhatsApp"
          
        #   # Marcar lead como sem WhatsApp
        #   lead.update(no_whatsapp: true)
          
        #   render json: {
        #     success: false,
        #     message: "❌ Este número não possui WhatsApp. O lead foi marcado como 'sem WhatsApp'.",
        #     lead_id: lead.id,
        #     whatsapp_disabled: true
        #   }
        #   return
        # end
        
        Rails.logger.info "✅ Número assumido como válido (validação por envio desativada), enfileirando mensagem real..."
        
        # Get delay multiplier for referrals with multiple instances
        delay_multiplier = get_delay_multiplier
        
        # Enfileira a mensagem com delay automático
        # ⚠️ IMPORTANTE: Aplicar cooldown APENAS se context == 'absent'
        result = EvolutionMessageQueueService.enqueue_message(
          phone: phone,
          message_text: message_text,
          media_details: media_details&.stringify_keys,
          instance_name: instance_name,
          lead_id: lead.id,
          user_id: current_user.id,
          appointment_id: appointment.id,
          skip_cooldown_check: (context != 'absent'),  # Pular cooldown EXCETO se for da view absent
          delay_multiplier: delay_multiplier
        )
        
        if result[:success]
          # Register that this message was sent to this appointment
          # This is the correct place to do it - when the message is actually sent
          add_message_sent(appointment, message.name)
          
          # Formata mensagem de sucesso com informações do enfileiramento
          # Inclui nome da instância para debug/transparência
          instance_abbr = result[:instance_name]&.split('_')&.last || 'default'
          
          delay_msg = if result[:delay_seconds] > 0
            " (enviando em #{result[:delay_seconds]}s - posição #{result[:position_in_queue]} na fila #{instance_abbr})"
          else
            " (enviando agora)"
          end
          
          render json: { 
            success: true, 
            message: "Mensagem enfileirada com sucesso!#{delay_msg}",
            delay_seconds: result[:delay_seconds],  # ← Adicionar aqui para JavaScript
            queue_info: {
              position: result[:position_in_queue],
              delay_seconds: result[:delay_seconds],
              estimated_send_time: result[:estimated_send_time]&.strftime('%H:%M:%S'),
              instance_name: result[:instance_name]
            },
            lead_id: lead.id,
            appointment_id: appointment.id,
            messages_sent: appointment.reload.messages_sent.join(', ')  # Updated list for UI
          }
        else
          # Marcar lead como "sem WhatsApp" quando houver erro
          if lead.present?
            lead.update(no_whatsapp: true)
            Rails.logger.info "❌ Lead #{lead.id} marcado como sem WhatsApp devido a erro no envio"
          end
          
          render json: { 
            success: false, 
            message: "Erro ao enfileirar mensagem: #{result[:error]}",
            lead_id: lead.id,
            whatsapp_disabled: true # Flag para atualizar UI
          }
        end
      rescue => e
        Rails.logger.error "Error in send_evolution_message: #{e.message}"
        
        # Marcar lead como "sem WhatsApp" também em caso de exceção
        if lead.present?
          lead.update(no_whatsapp: true)
          Rails.logger.info "❌ Lead #{lead.id} marcado como sem WhatsApp devido a exceção: #{e.message}"
        end
        
        render json: { 
          success: false, 
          message: "Erro interno: #{e.message}",
          lead_id: lead&.id,
          whatsapp_disabled: true # Flag para atualizar UI
        }
      end
    end

    def refresh_preview
      begin
        message_text = params[:message_text] || ""
        
        # Get a new random appointment
        sample_appointment = get_sample_appointment_for_preview
        
        # Format the preview with the new appointment data
        preview_text = format_placeholder_preview(message_text, sample_appointment)
        
        # Generate patient info text
        patient_info = if sample_appointment.respond_to?(:invitation) && sample_appointment.invitation.respond_to?(:lead)
          "Exemplo baseado em agendamento real do paciente: <strong>#{sample_appointment.invitation.lead&.name || sample_appointment.invitation.patient_name}</strong>"
        else
          "Exemplo com dados fictícios (nenhum agendamento encontrado no banco)"
        end
        
        render json: {
          success: true,
          original_text: message_text,
          preview_text: preview_text.gsub("\n", "<br>"),
          patient_info: patient_info
        }
      rescue => e
        Rails.logger.error "Error in refresh_preview: #{e.message}"
        render json: {
          success: false,
          error: e.message
        }
      end
    end
  
    private

    # Staff global view with Meta operational — show Evolution/Meta automation UI.
    def show_automation_channel_ui?
      return false if referral?(current_user)
      return false if @viewing_referral.present?
      return false unless current_account&.meta_whatsapp_enabled?

      true
    end

    def load_automation_index_state
      @show_automation_channel_ui = show_automation_channel_ui?
      @clinic_automation_channel = current_account.effective_clinic_automation_channel
      @meta_automation_available = current_account.clinic_automation_meta_available?
      @automation_tab = params[:tab].presence_in(%w[evolution meta]) || "evolution"
      @clinic_meta_automation_by_purpose = {}
      @meta_automation_viewing_all_externals = false
      @meta_automation_by_location = []
      @meta_automation_service_location_id = nil
      @meta_automation_location_label = "Interno"
      @meta_automation_enabled_map = {}
      return unless @show_automation_channel_ui && @meta_automation_available

      @clinic_meta_automation_by_purpose = ClinicMetaAutomationQuery.grouped_by_purpose(current_account)
      template_ids = @clinic_meta_automation_by_purpose.values.flatten.map(&:id)

      if multi_service_locations_enabled? && @viewing_referral.nil? && !referral?(current_user)
        loc_id = current_service_location_id.to_s
        if loc_id == "all"
          @meta_automation_viewing_all_externals = true
          @meta_automation_by_location = ServiceLocation.order(:name).map do |location|
            [
              location,
              ClinicMetaAutomationPreference.enabled_map_for(
                template_ids: template_ids,
                service_location_id: location.id
              )
            ]
          end
        else
          @meta_automation_service_location_id = loc_id.blank? ? nil : loc_id.to_i
          @meta_automation_location_label = meta_automation_location_label(@meta_automation_service_location_id)
          @meta_automation_enabled_map = ClinicMetaAutomationPreference.enabled_map_for(
            template_ids: template_ids,
            service_location_id: @meta_automation_service_location_id
          )
        end
      else
        @meta_automation_enabled_map = ClinicMetaAutomationPreference.enabled_map_for(
          template_ids: template_ids,
          service_location_id: nil
        )
      end
    end

    # @param raw [String, Integer, nil]
    # @return [Integer, nil]
    def normalize_meta_automation_service_location_id(raw)
      return nil if raw.blank? || raw.to_s == "internal"
      return raw.to_i if raw.to_s.match?(/\A\d+\z/)

      nil
    end

    # @param service_location_id [Integer, nil]
    # @return [String]
    def meta_automation_location_label(service_location_id)
      return "Interno" if service_location_id.blank?

      ServiceLocation.find_by(id: service_location_id)&.name || "Local desconhecido"
    end

    # Approved Meta templates matching clinic slot message_type.
    #
    # @param message_type [String]
    # @return [ActiveRecord::Relation]
    def meta_templates_for_slot(message_type)
      waba_ids = current_account.meta_business_accounts.active.select(:id)
      MetaTemplate
        .joins(:meta_business_account)
        .where(meta_business_accounts: { id: waba_ids })
        .clinic_automation_candidates(message_type)
        .order(:name)
        .select { |t| t.clinic_automation_ready? || t.approved? }
    end

    # Meta column + auto-sync apply only to global staff messages (referral_id nil).
    def show_lead_message_meta_column?
      false
    end

    def load_lead_message_meta_templates_index
      @meta_templates_by_lead_message_id = {}
    end

    # register that this message was sent to this appointment
    def add_message_sent(appointment, name)
      unless appointment.messages_sent.include? name
        appointment.messages_sent << name
        appointment.save
      end
    end

    def get_message(message, lead, service)
      Rails.logger.debug "Entering get_message method"
      Rails.logger.debug "Message: #{message.inspect}"
      Rails.logger.debug "Lead: #{lead.inspect}"
      Rails.logger.debug "Service: #{service.inspect}"

      return { text: "", media: nil } if message.nil?
      
      result = message.text
      Rails.logger.debug "Initial result: #{result.inspect}"

      return { text: "", media: nil } if result.nil?

      # Escolha aleatória de segmentos de texto
      result = result.gsub(/\[.*?\]/) do |match|
        options = match.tr('[]', '').split('|')
        options.sample
      end

      # Substituições de texto padrão (LINK_AUTO_MARCACAO only when account has self_booking_enabled)
      link_value = (defined?(current_account) && current_account&.self_booking_enabled?) ? generate_self_booking_link(lead) : ""
      result = result.gsub("{PRIMEIRO_NOME_PACIENTE}", lead.name.split(" ").first)
               .gsub("{NOME_COMPLETO_PACIENTE}", lead.name)
               .gsub("{LINK_AUTO_MARCACAO}", link_value)
               .gsub("\n", "%0A")
               .gsub("\r\n", "%0A")

      if service.present?
        # Substituições relacionadas ao serviço
        result = result.gsub("{DIA_SEMANA_ATENDIMENTO}", I18n.l(service&.date, format: "%A").to_s)
                       .gsub("{MES_DO_ATENDIMENTO}", I18n.l(service.date, format: "%B").to_s)
                       .gsub("{DIA_ATENDIMENTO_NUMERO}", service&.date&.strftime("%d").to_s)
                       .gsub("{HORARIO_DE_INICIO}", appointment.effective_start_time.strftime("%H:%M").to_s)
                       .gsub("{HORARIO_DE_TERMINO}", appointment.effective_end_time.strftime("%H:%M").to_s)
                       .gsub("{DATA_DO_ATENDIMENTO}", service&.date&.strftime("%d/%m/%Y").to_s)
      end

      # Extract media details (both from attached files and URL-based media)
      media_details = extract_media_details(message, result)
      
      # Remove URL-based media tags from final message if present
      final_message = result.gsub(/\[url=".*?"\s+legenda=".*?"\s+tipo=".*?"\]/, '')

      Rails.logger.debug "Final result: #{final_message.inspect}"
      Rails.logger.debug "Media details: #{media_details.inspect}"
      
      { text: final_message.strip, media: media_details }
    end
    
    # Extract media details from both attached files and URL-based media in text
    def extract_media_details(message, text)
      # Priority 1: Check for attached file
      if message.has_media?
        return {
          url: message.media_url,
          caption: message.media_caption.present? ? message.media_caption : '',
          type: message.whatsapp_media_type
        }
      end
      
      # Priority 2: Check for URL-based media in text (legacy support)
      media_regex = /\[url="(?<url>[^"]+)" legenda="(?<caption>[^"]*)" tipo="(?<type>[^"]+)"\]/
      match = text.match(media_regex)
      if match
        return {
          url: match[:url],
          caption: match[:caption],
          type: match[:type]
        }
      end
      
      # No media found
      nil
    end
  
    def set_message
      @message = LeadMessage.find(params[:id])
    end

    def check_message_permissions
      # ESSENTIAL: Operator+ (can_manage_lead_messages?) may edit/delete any message type.
      return if can_manage_lead_messages?

      # Clinical assistant and others: only "outro" messages
      unless @message.message_type == 'outro'
        redirect_to lead_messages_path, alert: 'Você não tem permissão para modificar mensagens de sistema. Operadores e gerentes podem fazer isso.'
      end
    end
  
    def message_params
      permitted = [:name, :text, :message_type, :service_type_id, :media_file, :media_caption, :media_type]
      permitted << :service_location_id if multi_service_locations_enabled?
      params.require(:lead_message).permit(permitted)
    end

    # ESSENTIAL: Filter lead messages by service_location.
    # "" = Interno (nil); "all" = all externals; id = specific location.
    def filter_messages_by_location(scope, location_id)
      case location_id.to_s
      when "all"
        scope.where.not(service_location_id: nil)
      when ""
        scope.where(service_location_id: nil)
      else
        scope.where(service_location_id: location_id)
      end
    end

    # Normalize service_location_id from form: "internal" -> nil, "" -> nil when required.
    def normalize_service_location_param(raw)
      return nil if raw.blank? || raw.to_s == "internal"
      raw
    end


    # Get the instance name to use for sending messages
    # Uses round-robin for referrals with multiple instances
    def get_instance_name
      if respond_to?(:referral?) && referral?(current_user)
        # Use referral's WhatsApp instance with round-robin rotation
        referral = user_referral
        instance = referral&.next_evolution_instance_name
        
        Rails.logger.info "🔍 Referral detected - ID: #{referral&.id}, Name: #{referral&.name}"
        Rails.logger.info "🔍 Selected instance (round-robin): #{instance.inspect}"
        Rails.logger.info "🔍 Connected instances: #{referral&.connected_instance_names&.join(', ')}"
        Rails.logger.info "🔍 Delay multiplier: #{referral&.evolution_delay_multiplier}"
        
        if instance.blank?
          Rails.logger.warn "⚠️ Referral #{referral&.id} não tem nenhuma instância conectada!"
        end
        
        instance
      else
        # Use account's instance 2
        instance = Account.first&.evolution_instance_name_2
        
        Rails.logger.info "🔍 Account user detected"
        Rails.logger.info "🔍 Account evolution_instance_name_2: #{instance.inspect}"
        
        if instance.blank?
          Rails.logger.warn "⚠️ Account não tem evolution_instance_name_2 configurado!"
        end
        
        instance
      end
    end

    # Check if we can send via Evolution API
    # Supports multiple instances for referrals
    def can_send_via_evolution?
      begin
        current_account = Account.first
        if respond_to?(:referral?) && referral?(current_user)
          # For referrals, check if they have any connected WhatsApp instance
          if respond_to?(:user_referral)
            referral = user_referral
            return referral&.has_connected_instances?
          else
            return false
          end
        else
          # For accounts, check if instance 2 is connected
          return Account.first&.evolution_instance_name_2.present? && current_account&.instance_2_connected
        end
      rescue => e
        Rails.logger.error "Error in can_send_via_evolution?: #{e.message}"
        return false
      end
    end

    
    # Returns the delay multiplier based on number of connected instances
    # With 2 instances: returns 0.5 (half the delay)
    # With 3 instances: returns 0.33 (1/3 the delay)
    def get_delay_multiplier
      if respond_to?(:referral?) && referral?(current_user)
        referral = user_referral
        referral&.evolution_delay_multiplier || 1.0
      else
        1.0
      end
    end

    # ============================================================================
    # Generate Self-Booking Link for Lead
    # 
    # Creates a unique self-booking URL that allows the patient to self-schedule.
    # 
    # TWO SEPARATE TRACKING CONCEPTS:
    # 1. ref (referral attribution) - WHO GETS THE COMMISSION
    #    - Based on 180-day grace period rule
    #    - Determines which referral gets credited for the booking
    # 
    # 2. reg_by (registered by) - WHO SHARED THE LINK (effort tracking)
    #    - Tracks which user sent/shared the link
    #    - Separate from commission - tracks work effort
    #    - Example: Assistant Jussara sends link -> reg_by=jussara_user_id
    #              But commission goes to the original referral (ref param)
    # 
    # @param lead [Lead] The lead to generate the link for
    # @return [String] Full URL for self-booking
    # ============================================================================
    def generate_self_booking_link(lead)
      return "" unless lead.present?
      
      # Build URL parameters
      url_params = {}
      
      # 1. Determine referral attribution (who gets commission)
      referral_id = determine_referral_for_link(lead)
      url_params[:ref] = referral_id if referral_id.present?
      
      # 2. ESSENTIAL: Track who shared/sent the link (effort tracking)
      # If there's a logged-in user, include their ID so we know who did the work
      if defined?(current_user) && current_user.present?
        url_params[:reg_by] = current_user.id
        Rails.logger.info "[SelfBookingLink] Link shared by user: #{current_user.name} (ID: #{current_user.id})"
      end
      
      # Build the self-booking path with parameters
      self_booking_path = clinic_management.self_booking_path(lead.self_booking_token!, url_params)
      
      # Build full URL using request if available, otherwise use main app's ApplicationController.app_url
      if defined?(request) && request.present?
        "#{request.base_url}#{self_booking_path}"
      else
        # Fallback using main app's ApplicationController (:: prefix for global namespace)
        base_url = ::ApplicationController.app_url.chomp('/')
        "#{base_url}#{self_booking_path}"
      end
    end

    # ============================================================================
    # Determine Referral ID for Self-Booking Link
    # 
    # Priority order for referral attribution (COMMISSION):
    # 1. Current user is a referral -> use their referral ID (they're sending the message)
    # 2. Lead has attributed referral (within 180-day grace period) -> use that referral
    # 3. No referral -> return nil (will be attributed to "Local" on booking)
    # 
    # NOTE: This is separate from reg_by (who shared the link).
    # ref = who gets paid (commission)
    # reg_by = who did the work (effort tracking)
    # 
    # @param lead [Lead] The lead to check for referral attribution
    # @return [Integer, nil] The referral ID to include in the link, or nil
    # ============================================================================
    def determine_referral_for_link(lead)
      # CASE 1: Current user is a referral - they get credit for their own messages
      if respond_to?(:referral?) && referral?(current_user) && respond_to?(:user_referral) && user_referral.present?
        Rails.logger.info "[SelfBookingLink] Using current user's referral: #{user_referral.name} (ID: #{user_referral.id})"
        return user_referral.id
      end
      
      # CASE 2: Check if lead has an attributed referral (180-day grace period)
      # This ensures referrals get credit even when clinic staff sends messages
      attributed_referral = lead.current_attributed_referral
      if attributed_referral.present?
        Rails.logger.info "[SelfBookingLink] Using lead's attributed referral: #{attributed_referral.name} (ID: #{attributed_referral.id}) - within 180-day grace period"
        return attributed_referral.id
      end
      
      # CASE 3: No referral attribution
      Rails.logger.info "[SelfBookingLink] No referral attribution for lead #{lead.id} - will be Local"
      nil
    end
  end
end
