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
      byebug
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

    def replace_attributes
      begin
        message = LeadMessage.find(params[:message_id])
        order = Order.find(params[:order_id])
        customer = order.customer
        message = get_message(message, customer, order)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
                  "whatsapp-link-" + order.id.to_s, 
                  partial: "messages/whatsapp_link", 
                  locals: { phone_number: customer.phone_1, message: message })
          end
        end
      rescue
      end
    end
  
    private

    def get_message(message, customer, order)
      Leadmessage.text
      .gsub("{PRIMEIRO_NOME_CLIENTE}", customer.name.split(" ").first)
      .gsub("{NOME_COMPLETO_CLIENTE}", customer.name)
      .gsub("{OS}", order.os.to_s)
      .gsub("{DATA_COMPRA}", order.created_at.strftime("%d/%m/%Y"))
      .gsub("{DATA_ENTREGA}", order.delivery_date.strftime("%d/%m/%Y"))
      .gsub("{VALOR_TOTAL}", helpers.currency_br(order.total_amount))
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
