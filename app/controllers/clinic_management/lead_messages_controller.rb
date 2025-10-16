module ClinicManagement
  class LeadMessagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_message, only: [:show, :edit, :update, :destroy]
    skip_before_action :redirect_referral_users
    include GeneralHelper
    include MessagesHelper
    require 'httparty'

    def index
      # Show only messages for the current referral, or global messages if not referral
      if referral?(current_user)
        @messages = LeadMessage.where(referral_id: user_referral.id)
      else
        @messages = LeadMessage.where(referral_id: nil)
      end
      @messages_by_type = @messages.order(created_at: :asc).group_by(&:message_type)
    end
  
    def new
      @message = LeadMessage.new
    end
  
    def create
      @message = LeadMessage.new(message_params)
      # If the user is a referral, associate the message with their referral_id
      @message.referral_id = user_referral.id if referral?(current_user)
      if referral?(current_user)
        @message.message_type = 3
      end
      

      if @message.save
        redirect_to lead_messages_path, notice: 'Mensagem customizada criada com sucesso.'
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
      if @message.update(message_params)
        if referral?(current_user)
          @message.message_type = 3
        end
        redirect_to lead_messages_path
      else
        render :edit
      end
    end
  
    def destroy
      @message.destroy
      redirect_to lead_messages_path, notice: 'Mensagem customizada excluída com sucesso.'
    end

    def build_message
      begin
        message = LeadMessage.find_by(id: params[:custom_message_id])
        appointment = Appointment.find_by(id: params[:appointment_id])
        add_message_sent(appointment, message.name)
        lead = Lead.find_by(id: params[:lead_id])
        message_data = get_message(message, lead, appointment.service)
        
        # Check if we can use Evolution API for automatic sending (with error handling)
        can_use_evolution = false
        begin
          can_use_evolution = can_send_via_evolution?
        rescue => evolution_error
          Rails.logger.error "Error checking Evolution API availability: #{evolution_error.message}"
          can_use_evolution = false
        end
        
        render turbo_stream: [
          turbo_stream.append(
            "whatsapp-link-#{lead.id}", 
            partial: "clinic_management/lead_messages/whatsapp_link", 
            locals: { 
              phone_number: lead.phone, 
              message: message_data[:text],
              media_details: message_data[:media],
              lead_id: lead.id,
              appointment_id: appointment.id,
              can_use_evolution: can_use_evolution,
              message_id: message.id
            }
          ),
          turbo_stream.update(
            "messages-sent-#{appointment.id}", 
            appointment.messages_sent.join(', ')
          )
        ]        
      rescue => e
        Rails.logger.error "Error in build_message: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Always provide fallback manual option even on error
        lead = Lead.find_by(id: params[:lead_id])
        appointment = Appointment.find_by(id: params[:appointment_id])
        
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
              message_id: nil
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
        
        Rails.logger.info "📋 Found records - Message: #{message&.id}, Appointment: #{appointment&.id}, Lead: #{lead&.id}"
        
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
        
        # Enfileira a mensagem com delay automático
        result = EvolutionMessageQueueService.enqueue_message(
          phone: phone,
          message_text: message_text,
          media_details: media_details&.stringify_keys,
          instance_name: instance_name,
          lead_id: lead.id  # Adiciona lead_id para verificação de cooldown
        )
        
        if result[:success]
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
            lead_id: lead.id
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

      # Substituições de texto padrão
      result = result.gsub("{PRIMEIRO_NOME_PACIENTE}", lead.name.split(" ").first)
               .gsub("{NOME_COMPLETO_PACIENTE}", lead.name)
               .gsub("\n", "%0A")
               .gsub("\r\n", "%0A")

      if service.present?
        # Substituições relacionadas ao serviço
        result = result.gsub("{DIA_SEMANA_ATENDIMENTO}", I18n.l(service&.date, format: "%A").to_s)
                       .gsub("{MES_DO_ATENDIMENTO}", I18n.l(service.date, format: "%B").to_s)
                       .gsub("{DIA_ATENDIMENTO_NUMERO}", service&.date&.strftime("%d").to_s)
                       .gsub("{HORARIO_DE_INICIO}", service.start_time.strftime("%H:%M").to_s)
                       .gsub("{HORARIO_DE_TERMINO}", service.end_time.strftime("%H:%M").to_s)
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
  
    def message_params
      params.require(:lead_message).permit(:name, :text, :message_type, :service_type_id, :media_file, :media_caption, :media_type)
    end

    # Get the instance name to use for sending messages
    def get_instance_name
      if respond_to?(:referral?) && referral?(current_user)
        # Use referral's WhatsApp instance
        referral = user_referral
        instance = referral&.evolution_instance_name
        
        Rails.logger.info "🔍 Referral detected - ID: #{referral&.id}, Name: #{referral&.name}"
        Rails.logger.info "🔍 Referral evolution_instance_name: #{instance.inspect}"
        Rails.logger.info "🔍 Referral instance_connected: #{referral&.instance_connected}"
        
        if instance.blank?
          Rails.logger.warn "⚠️ Referral #{referral&.id} não tem evolution_instance_name configurado!"
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
    def can_send_via_evolution?
      begin
        current_account = Account.first
        if respond_to?(:referral?) && referral?(current_user)
          # For referrals, check if their WhatsApp instance is connected
          if respond_to?(:user_referral)
            referral = user_referral
            return referral&.evolution_instance_name.present? && referral&.instance_connected
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

    # Send message via Evolution API (supports both text and media)
    def send_via_evolution_api(message_text, phone, media_details = nil)        
      instance_name = nil
      if referral?(current_user)
        # Use referral's WhatsApp instance
        referral = user_referral
        instance_name = referral&.evolution_instance_name
      else
        # Use account's instance 2
        instance_name = Account.first.evolution_instance_name_2
      end

      Rails.logger.info "🚀 Calling send_evolution_message_with_media with phone: #{phone}, instance: #{instance_name}"
      # Use the helper function to send the message
      response = send_evolution_message_with_media(phone, message_text, media_details, instance_name)
      
      Rails.logger.info "📱 Evolution API response: #{response.inspect}"
      
      if response.success?
        { success: true }
      else
        error_message = response.parsed_response.dig('response', 'message')&.join(', ') || 'Erro desconhecido'
        { success: false, error: error_message }
      end
    end
  end
end
