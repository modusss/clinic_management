module ClinicManagement
  class LeadMessagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_message, only: [:show, :edit, :update, :destroy]
    skip_before_action :redirect_referral_users
    include GeneralHelper

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
        message = get_message(message, lead, appointment.service)
        
        render turbo_stream: [
          turbo_stream.append(
            "whatsapp-link-#{lead.id}", 
            partial: "clinic_management/lead_messages/whatsapp_link", 
            locals: { 
              phone_number: lead.phone, 
              message: message,
              lead_id: lead.id,
              appointment_id: appointment.id
            }
          ),
          turbo_stream.update(
            "messages-sent-#{appointment.id}", 
            appointment.messages_sent.join(', ')
          )
        ]        
      rescue => e
        Rails.logger.error "Error in build_message: #{e.message}"
        render turbo_stream: turbo_stream.replace(
          "whatsapp-link-#{params[:lead_id]}", 
          html: "<p>Erro ao gerar mensagem.</p>"
        )
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

      return "" if message.nil?
      
      result = message.text
      Rails.logger.debug "Initial result: #{result.inspect}"

      return "" if result.nil?

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

      Rails.logger.debug "Final result: #{result.inspect}"
      result
    end
  
    def set_message
      @message = LeadMessage.find(params[:id])
    end
  
    def message_params
      params.require(:lead_message).permit(:name, :text, :message_type, :service_type_id)
    end
  end
end
