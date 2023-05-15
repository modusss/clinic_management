module ClinicManagement
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[ show edit update destroy ]
    include TimeSlotsHelper
    # GET /services
    def index
      @services = ClinicManagement::Service.all
      @rows = @services.order(:date).reverse.each_with_index.map do |ser,index|
      total_appointments = ser.appointments.count
      scheduled = ser.appointments.where(attendance: true).count
      rescheduled = ser.appointments.where(status: "remarcado").count
      canceleds = ser.appointments.where(status: "cancelado").count
        [
          { header: "#", content: index + 1 },
          { header: "Data", content: ser.date.strftime("%d/%m/%Y") },
          { header: "Dia da semana", content: helpers.show_week_day(ser.weekday) },
          { header: "Início", content: ser.start_time.strftime("%H:%M") },
          { header: "Fim", content: ser.end_time.strftime("%H:%M") },
          { header: "Pacientes", content: total_appointments },
          { 
            header: "Presentes", 
            content: "#{scheduled} <span class='bg-blue-200 text-blue-700 p-1 rounded'>(#{(scheduled.to_f/total_appointments*100).round(2)}%)</span>".html_safe, 
            class: "text-blue-700" 
          },
          { 
            header: "Remarcados", 
            content: "#{rescheduled} <span class='bg-green-200 text-green-700 p-1 rounded'>(#{(rescheduled.to_f/total_appointments*100).round(2)}%)</span>".html_safe, 
            class: "text-green-600" 
          },
          { 
            header: "Cancelados", 
            content: "#{canceleds} <span class='bg-red-200 text-red-700 p-1 rounded'>(#{(canceleds.to_f/total_appointments*100).round(2)}%)</span>".html_safe, 
            class: "text-red-600" 
          },                
          { header: "Detalhes", content: helpers.link_to("Detalhes", ser, class: "text-blue-500 hover:text-blue-700") }
        ]        
      end
    end

    # GET /services/1
    def show
      @appointments = @service.appointments.includes(:invitation).sort_by { |ap| ap.invitation.patient_name }
      @rows = @appointments.map.with_index(1) do |ap, index|
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
          { 
            header: "Comparecimento", 
            content: ap.attendance ? "Sim" : "Não", 
            id: "attendance-#{ap.id}", 
            class: ap.attendance ? "text-green-600" : "text-red-600" 
          },          
          { header: "Nº de Comparecimentos", content: ap.lead.appointments.count },
          { 
            header: "Ação", 
            content: set_appointment_button(ap), 
            id: "set-attendance-button-#{ap.id}", 
            class: "pt-2 pb-0"
          },          
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
        helpers.button_to('Marcar como presente', set_attendance_appointment_path(ap), method: :patch, remote: true, class: "py-2 px-4 bg-blue-500 text-white rounded hover:bg-blue-700")
      end
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
