module ClinicManagement
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[ show edit update destroy ]
    include TimeSlotsHelper
    # GET /services
    def index
      @services = ClinicManagement::Service.all
      @rows = @services.order(:date).reverse.each_with_index.map do |ser,index|
        [
          { header: "#", content: index + 1 },
          { header: "Data", content: ser.date.strftime("%d/%m/%Y") },
          { header: "Dia da semana", content: helpers.show_week_day(ser.weekday) },
          { header: "Início", content: ser.start_time.strftime("%H:%M") },
          { header: "Fim", content: ser.end_time.strftime("%H:%M") },
          { header: "Pacientes", content: ser.appointments.count },
          { header: "Presentes", content: ser.appointments.where(attendance: true).count, class: "text-blue-700" },
          { header: "Agendados", content: ser.appointments.where(status: "agendado").count, class: "text-yellow-600" },
          { header: "Remarcados", content: ser.appointments.where(status: "remarcado").count, class: "text-green-600" },
          { header: "Cancelados", content: ser.appointments.where(status: "cancelado").count, class: "text-red-600" },
          { header: "Detalhes", content: helpers.link_to("Detalhes", ser, class: "text-blue-500 hover:text-blue-700") }
        ]        
      end
    end

    # GET /services/1
    def show
      @appointments = @service.appointments
      @rows = @appointments.order(:created_at).map.with_index(1) do |ap, index|
        [
          { header: "#", content: index },
          { header: "Paciente", content: ap.invitation.patient_name },
          { header: "Telefone", content: ap.lead.phone },
          { header: "Endereço", content: ap.invitation.lead.address },
          { header: "Região", content: ap.invitation.region.name },
          { header: "Indicação", content: ap.invitation.referral.name },
          { 
            header: "Status", 
            content: ap.status,
            class: case ap.status
                    when "agendado"
                      "text-yellow-600"
                    when "remarcado"
                      "text-orange-500"
                    when "cancelado"
                      "text-red-600"
                    else
                      ""
                    end
          },          
          { header: "Comparecimento", content: attendance_status(ap), id: "attendance-#{ap.id}", class: "text-blue-700" },
          { header: "Nº de Comparecimentos", content: ap.lead.appointments.count },
          { header: "Ação", content: set_appointment_button(ap), id: "set-attendance-button-#{ap.id}", class: "text-green-600" },
          { header: "Observações", content: ap.invitation.notes },
          { header: "Mensagem", content: "" },
          { header: "Remarcação", content: "", class: "text-orange-500" },
          { header: "Cancelar?", content: "", class: "text-red-600" },
          { header: "Cliente?", content: "", class: "text-purple-500" }
        ]                 
      end
      
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

      def set_appointment_button(ap)
        if ap.attendance.present?
          "--"
        else
          helpers.button_to('Presente ok', set_attendance_appointment_path(ap), method: :patch, remote: true, class: "")
        end
      end

      def attendance_status(ap)
        ap.attendance == true ? "Sim" : "Não"
      end

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
