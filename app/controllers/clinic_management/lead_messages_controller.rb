module ClinicManagement
  class LeadMessagesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_message, only: [:show, :edit, :update, :destroy]
    include GeneralHelper

    def index
      @messages = LeadMessage.all
=begin
      @rows = LeadMessage.all.map.with_index(1) do |mes, index|
        [
          { header: "#", content: index },
          { header: "Nome", content: mes.name },
          { header: "Convites", content: mes.text }
        ] 
      end
=end
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

    def replace_lead_attributes
      begin
        message = LeadMessage.find(params[:custom_message_id])
        lead = Lead.find(params[:lead_id])
        message = get_message(message, lead)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append(
                  "whatsapp-link-" + lead.id.to_s, 
                  partial: "clinic_management/lead_messages/whatsapp_link", 
                  locals: { phone_number: lead.phone, message: message })
          end
        end
      rescue
      end
    end
  
    private

    def get_message(message, lead)
      message.text
      .gsub("{PRIMEIRO_NOME_CLIENTE}", lead.name.split(" ").first)
      .gsub("{NOME_COMPLETO_CLIENTE}", lead.name)
      .gsub("\n", "%0A")
      .gsub("\r\n", "%0A")
    end
  
    def set_message
      @message = LeadMessage.find(params[:id])
    end
  
    def message_params
      params.require(:lead_message).permit(:name, :text)
    end
  end
end
