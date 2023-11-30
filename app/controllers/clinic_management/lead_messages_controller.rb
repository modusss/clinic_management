module ClinicManagement
  class LeadMessagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_message, only: [:show, :edit, :update, :destroy]
    include GeneralHelper

    def index
      @messages = LeadMessage.order(:message_type, created_at: :desc)
    end
  
    def new
      @message = LeadMessage.new
    end
  
    def create
      @message = LeadMessage.new(message_params)
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
        message = get_message(message, lead, appointment.service) # add service here
        render turbo_stream: [
          turbo_stream.append(
            "whatsapp-link-" + lead.id.to_s, 
            partial: "clinic_management/lead_messages/whatsapp_link", 
            locals: { phone_number: lead.phone, message: message }
          ),
          turbo_stream.update(
            "messages-sent-" + appointment.id.to_s, 
            appointment.messages_sent.join(', ')
          )
        ]        
      rescue
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
      result = message.text
        .gsub("{PRIMEIRO_NOME_PACIENTE}", lead.name.split(" ").first)
        .gsub("{NOME_COMPLETO_PACIENTE}", lead.name)
        .gsub("\n", "%0A")
        .gsub("\r\n", "%0A")
      if service.present?
        appointments = ClinicManagement::Appointment.where(service_id: service.id)
        # patient_names = appointments.map do |appointment|
          # invitation = ClinicManagement::Invitation.find(appointment.invitation_id)
          # invitation.patient_name != lead.name ? invitation.patient_name : nil
        # end.compact
    
        # patient_list = patient_names.uniq.join(", ")
        # patient_list = "Paciente(s): #{patient_list}" unless patient_list.empty?
    
        result = result
          .gsub("{DIA_SEMANA_ATENDIMENTO}", I18n.l(service.date, format: "%A"))
          .gsub("{MES_DO_ATENDIMENTO}", I18n.l(service.date, format: "%B"))
          .gsub("{DIA_ATENDIMENTO_NUMERO}", service&.date&.strftime("%d"))
          .gsub("{HORARIO_DE_INICIO}", service.start_time.strftime("%H:%M"))
          .gsub("{HORARIO_DE_TERMINO}", service.end_time.strftime("%H:%M"))
          .gsub("{DATA_DO_ATENDIMENTO}", service&.date&.strftime("%d/%m/%Y"))
          # .gsub("{LISTA_DE_PACIENTES}", patient_list)
      end
    
      result
    end
  
    def set_message
      @message = LeadMessage.find(params[:id])
    end
  
    def message_params
      params.require(:lead_message).permit(:name, :text, :message_type)
    end
  end
end
