module ClinicManagement
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[ show edit update destroy ]
    include TimeSlotsHelper
    # GET /services
    def index
      @rows = process_services_data(ClinicManagement::Service.includes(:appointments).order(date: :desc))
    end

    # GET /services/1
    def show
      @rows = process_appointments_data(@service.appointments.includes(:invitation, :lead))       
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

    def process_appointments_data(appointments)
      sorted_appointments = appointments.sort_by { |ap| ap.invitation.patient_name }
      
      sorted_appointments.map.with_index(1) do |ap, index|
        attendance_class, status_class = appointment_classes(ap)
  
        [
          { header: "#", content: index },
          { header: "Paciente", content: ap.invitation.patient_name },
          { header: "Telefone", content: ap.lead.phone },
          { header: "Endereço", content: ap.invitation.lead.address },
          { header: "Região", content: ap.invitation.region.name },
          { header: "Indicação", content: ap.invitation.referral.name },
          { header: "Status", content: ap.status, id: "status-#{ap.id}", class: status_class },          
          { header: "Comparecimento", content: ap.attendance ? "Sim" : "Não", id: "attendance-#{ap.id}", class: attendance_class },          
          { header: "Nº de Comparecimentos", content: ap.lead.appointments.count },
          { header: "Ação", content: set_appointment_button(ap), id: "set-attendance-button-#{ap.id}", class: "pt-2 pb-0" },          
          { header: "Observações", content: ap.invitation.notes },
          { header: "Mensagem", content: generate_message_content(ap), id: "whatsapp-link-#{ap.lead.id}" },
          { header: "Remarcação", content: "", class: "text-orange-500" },
          { header: "Cancelar?", content: set_cancel_button(ap), id: "cancel-attendance-button-#{ap.id}", class: "pt-2 pb-0" },
          { header: "Cliente?", content: "", class: "text-purple-500" }
        ]                 
      end
    end
  
    def appointment_classes(appointment)
      attendance_class = appointment.attendance ? "text-green-600" : "text-red-600"
  
      status_class = case appointment.status
                     when "agendado"
                       "text-yellow-600"
                     when "remarcado"
                       "text-orange-600"
                     when "cancelado"
                       "text-red-600"
                     else
                       ""
                     end
  
      [attendance_class, status_class]
    end
  
    def generate_message_content(appointment)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: appointment.lead }
      )
    end

    def process_services_data(services)
      services.map.with_index do |ser, index|
        total_appointments, scheduled, rescheduled, canceleds = appointment_counts(ser)
        [
          { header: "#", content: index + 1 },
          { header: "Data", content: ser.date.strftime("%d/%m/%Y") },
          { header: "Dia da semana", content: helpers.show_week_day(ser.weekday) },
          { header: "Início", content: ser.start_time.strftime("%H:%M") },
          { header: "Fim", content: ser.end_time.strftime("%H:%M") },
          { header: "Pacientes", content: total_appointments },
          percentage_content("Presentes", scheduled, total_appointments, "text-blue-700", "bg-blue-200"),
          percentage_content("Remarcados", rescheduled, total_appointments, "text-green-600", "bg-green-200"),
          percentage_content("Cancelados", canceleds, total_appointments, "text-red-600", "bg-red-200"),
          { header: "Detalhes", content: helpers.link_to("Detalhes", ser, class: "text-blue-500 hover:text-blue-700") }
        ]
      end
    end

    def set_appointment_button(ap)
      if ap.attendance.present?
        "--"
      else
        helpers.button_to('Marcar como presente', set_attendance_appointment_path(ap), method: :patch, remote: true, class: "py-2 px-4 bg-blue-500 text-white rounded hover:bg-blue-700")
      end
    end

    def appointment_counts(service)
      appointments = service.appointments
      total_appointments = appointments.count
      scheduled = appointments.where(attendance: true).count
      rescheduled = appointments.where(status: "remarcado").count
      canceleds = appointments.where(status: "cancelado").count
      [total_appointments, scheduled, rescheduled, canceleds]
    end
  
    def percentage_content(header, count, total, text_class, bg_class)
      {
        header: header,
        content: "#{count} <span class='#{bg_class} #{text_class} p-1 rounded'>(#{percentage(count, total)}%)</span>".html_safe,
        class: text_class
      }
    end
  
    def percentage(count, total)
      (count.to_f / total * 100).round(2)
    end

    def set_cancel_button(ap)
      if ["agendado", "remarcado"].include? ap.status
        helpers.button_to('Cancelar', cancel_attendance_appointment_path(ap), method: :patch, remote: true, class: "py-2 px-4 bg-red-500 text-white rounded hover:bg-red-700")
      else
        "--"
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
