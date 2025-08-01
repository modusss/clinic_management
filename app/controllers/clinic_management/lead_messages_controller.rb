module ClinicManagement
  class LeadMessagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_message, only: [:show, :edit, :update, :destroy]
    skip_before_action :redirect_referral_users
    include GeneralHelper
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
        # Ensure phone has country code
        phone = "55#{phone}" unless phone.start_with?('55')
        
        # Send via Evolution API (with media support)
        response = send_via_evolution_api(message_text, phone, media_details)
        
        if response[:success]
          render json: { 
            success: true, 
            message: 'Mensagem enviada automaticamente via WhatsApp!' 
          }
        else
          render json: { 
            success: false, 
            message: "Erro ao enviar mensagem: #{response[:error]}" 
          }
        end
      rescue => e
        Rails.logger.error "Error in send_evolution_message: #{e.message}"
        render json: { 
          success: false, 
          message: "Erro interno: #{e.message}" 
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

    # Check if we can send via Evolution API
    def can_send_via_evolution?
      begin
        # Check if we have the required methods available
        return false unless respond_to?(:current_user) && current_user.present?
        return false unless respond_to?(:current_account) && current_account.present?
        
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
          return current_account&.evolution_instance_name_2.present? && current_account&.instance_2_connected
        end
      rescue => e
        Rails.logger.error "Error in can_send_via_evolution?: #{e.message}"
        return false
      end
    end

    # Send message via Evolution API (supports both text and media)
    def send_via_evolution_api(message_text, phone, media_details = nil)
      begin
        # Check if we have the required methods and data available
        return { success: false, error: 'Usuário não encontrado' } unless respond_to?(:current_user) && current_user.present?
        return { success: false, error: 'Conta não encontrada' } unless respond_to?(:current_account) && current_account.present?
        
        instance_name = nil
        api_key = current_account.evolution_api_key
        base_url = current_account.evolution_base_url
        
        if referral?(current_user)
          # Use referral's WhatsApp instance
          referral = user_referral
          instance_name = referral&.evolution_instance_name
        else
          # Use account's instance 2
          instance_name = current_account.evolution_instance_name_2
        end

        return { success: false, error: 'Configuração de WhatsApp não encontrada' } unless instance_name.present?
        return { success: false, error: 'Configuração da API não encontrada' } unless api_key.present? && base_url.present?

        headers = {
          'Content-Type' => 'application/json',
          'apikey' => api_key
        }
        
        # Check if we have media to send
        if media_details.present? && media_details[:url].present?
          # Send media message only (no separate text for images/audio)
          url = "#{base_url}/message/sendMedia/#{instance_name}"
          
          # Map media types to Evolution API format
          mediatype = case media_details[:type]
                     when 'image'
                       'image'
                     when 'audio'
                       'audio'
                     when 'video'
                       'video'
                     when 'document'
                       'document'
                     else
                       'document'
                     end
          
          # For images and audio, only send the media with caption
          # For documents and videos, we can include both caption and text
          caption_text = if ['image', 'audio'].include?(media_details[:type])
                          # Only caption for images and audio
                          media_details[:caption].present? ? media_details[:caption] : message_text
                        else
                          # Caption + text for documents and videos
                          [media_details[:caption], message_text].reject(&:blank?).join("\n\n")
                        end
          
          body = {
            number: phone,
            options: {
              delay: 10,
              presence: "composing",
              linkPreview: false
            },
            mediaMessage: {
              mediatype: mediatype,
              caption: caption_text.strip,
              media: media_details[:url]
            }
          }.to_json
        else
          # Send text message only
          url = "#{base_url}/message/sendText/#{instance_name}"
          body = {
            number: phone,
            text: message_text
          }.to_json
        end

        response = HTTParty.post(url, headers: headers, body: body)
        
        if response.success?
          { success: true }
        else
          error_message = response.parsed_response.dig('response', 'message')&.join(', ') || 'Erro desconhecido'
          { success: false, error: error_message }
        end
      rescue => e
        Rails.logger.error "Evolution API error: #{e.message}"
        { success: false, error: e.message }
      end
    end
  end
end
