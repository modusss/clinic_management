module ClinicManagement
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[ show edit update destroy ]
    include TimeSlotsHelper
    # GET /services
    def index
      @services = ClinicManagement::Service.all
      @services = @services.order(:date).reverse.each_with_index.map do |ser,index|
        [
          index + 1,
          ser.date.strftime("%d/%m/%Y"),
          helpers.show_week_day(ser.weekday),
          ser.start_time.strftime("%H:%M"),
          ser.end_time.strftime("%H:%M"),
          ser.appointments.count,
          helpers.link_to("Detalhes", ser, class: "text-blue-500 hover:text-blue-700")
        ]
      end
      @headers = ["#",
                "Data",
                "Dia da Semana",
                "Início",
                "Fim",
                "Pacientes",
                "Detalhes"]
    end

    # GET /services/1
    def show
      @appointments = @service.appointments
      @appointments_map = @appointments.order(:created_at).map.with_index(1) do |ap, index|
        [
          index,
          ap.invitation.patient_name,
          ap.lead.phone,
          ap.status,
          ap.invitation.referral.name,
          ap.invitation.region.name,
          ap.invitation.lead.address,
          ap.invitation.notes,
          ap.attendance.to_s,
          ap.lead.appointments.count,
          "botão",
          "",
          "",
          "",
          ""
        ]     
      end
      @headers = ["#",
                  "Paciente",
                  "Telefone",
                  "Status", 
                  "Indicação", 
                  "Região",
                  "Endereço",
                  "Observações",
                  "Comprecimento",
                  "Nº de Comparecimentos",
                  "Ação",
                  "Mensagem",
                  "Remarcação",
                  "Cancelar?",
                  "Cliente?"]
    end

    # GET /services/new
    def new
      @service = Service.new
    end

    # GET /services/1/edit
    def edit
    end

    # POST /services
    def create
      @service = Service.new(service_params)
      @time_slot = TimeSlot.find(service_params[:time_slot_id])
      @service.weekday = @time_slot.weekday
      @service.start_time = @time_slot.start_time
      @service.end_time = @time_slot.end_time
      if @service.save
        redirect_to @service, notice: "Atendimento criado com sucesso!"
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /services/1
    def update
      if @service.update(service_params)
        redirect_to @service, notice: "Service was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /services/1
    def destroy
      @service.destroy
      redirect_to services_url, notice: "Service was successfully destroyed."
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_service
        @service = Service.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def service_params
        params.require(:service).permit(:weekday, :start_time, :end_time, :date, :time_slot_id)
      end
  end
end
