module ClinicManagement
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[ show edit update destroy ]
    skip_before_action :redirect_referral_users, only: [:index_by_referral, :show_by_referral]
    include TimeSlotsHelper, GeneralHelper

    require 'cgi'

    # GET /services
    def index
      @referrals = Referral.all
      @rows = process_services_data(ClinicManagement::Service.includes(:appointments).order(date: :desc))
    end

    def index_by_referral
      @referral = Referral.find(params[:referral_id])
      @services = Rails.cache.read("referral_#{@referral.id}_services")
      if @services.nil?
        @services = Service.joins(appointments: {invitation: :referral})
                           .where(referrals: { id: @referral.id })
                           .order(date: :desc)
                           .distinct
      end
      @rows = process_services_data(@services)
    end
    
    
    # GET /services/1
    def show
      @rows = process_appointments_data(@service.appointments.includes(:invitation, :lead))       
    end

    def show_by_referral
      @referral = Referral.find(params[:referral_id])
      all_appointments = @referral.invitations.map(&:appointments).flatten
      all_services = all_appointments.map(&:service).uniq
      all_services = all_services.sort_by { |service| service.date }.reverse
      @service = all_services.find { |s| s.id == params[:id].to_i }
      @rows = process_appointments_by_referral_data(@service.appointments.includes(:invitation, :lead))
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
      json_params = decode_json(params[:service][:time_slot_id])
      @time_slot = TimeSlot.find(json_params["time_slot_id"])
      @service = Service.new
      @service.weekday = @time_slot.weekday
      @service.start_time = @time_slot.start_time
      @service.end_time = @time_slot.end_time
      @service.date = json_params["date"]
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
      unless @service.appointments.count > 0
        @service.destroy
        redirect_to services_url, notice: "Service was successfully destroyed."
      end
    end

    private

    def decode_json(json_str)
      while json_str.is_a?(String)
        begin
          json_str = JSON.parse(json_str)
        rescue JSON::ParserError
          break
        end
      end
      json_str
    end

    def process_appointments_by_referral_data(appointments)
      sorted_appointments = appointments.select { |appointment| appointment.invitation.referral_id == @referral.id }
      sorted_appointments.map.with_index(1) do |ap, index|
        lead = ap.lead
        new_appointment = ClinicManagement::Appointment.new
        invitation = ap.invitation
        [
          { header: "#", content: index },
          { header: "Paciente", content: invitation.patient_name },
          { header: "Comparecimento", content: ap.attendance ? "Sim" : "Não", id: "attendance-#{ap.id}", class: helpers.attendance_class(ap) },          
          { header: "Responsável", content: ((lead.name == invitation.patient_name) ? "" : lead.name) },
          { header: "Telefone", content: "<a target='_blank' href='#{helpers.whatsapp_link(lead.phone, set_zap_message(ap.service, invitation))}'>#{lead.phone}</a>".html_safe, class: "text-blue-500 hover:text-blue-700" },
          { header: "Remarcação", content: reschedule_form(new_appointment, ap), class: "text-orange-500" },
          { header: "Endereço", content: invitation.lead.address },
          { header: "Região", content: invitation.region.name },
          { header: "Status", content: ap.status, id: "status-#{ap.id}", class: helpers.status_class(ap) },          
          { header: "Observações", content: invitation.notes }
        ]
      end
    end

    def set_zap_message(service, invitation)
      message = "Oi #{invitation.patient_name.split.first}! Tudo bem?😊 Aqui é a #{invitation.referral.name}!\n\nLembra que tínhamos marcado aquele exame de vista para o dia de #{ I18n.l(service.date, format: "%A, %d/%m")}?\n\nVi que não deu para você comparecer... 😔\n\nQue tal a gente remarcar?\n\nAssim garantimos a saúde dos seus olhos e esclarecemos qualquer dúvida que você possa ter! 😊👓\n\nAguardo seu retorno, obrigado!"
      CGI::escape(message)
    end

    def process_appointments_data(appointments)
      sorted_appointments = appointments.sort_by { |ap| ap.invitation.patient_name }  
      sorted_appointments.map.with_index(1) do |ap, index|
        new_appointment = ClinicManagement::Appointment.new
        lead = ap.lead
        invitation = ap.invitation
        [
          { header: "#", content: index },
          { header: "Paciente", content: helpers.link_to(invitation.patient_name, lead_path(ap.lead), class: "text-blue-500 hover:text-blue-700") },
          { header: "Comparecimento", content: ap.attendance ? "Sim" : "Não", id: "attendance-#{ap.id}", class: helpers.attendance_class(ap) },          
          { header: "Responsável", content: ((lead.name == invitation.patient_name) ? "" : lead.name) },
          { header: "Telefone", content: lead.phone },
          { header: "Endereço", content: invitation.lead.address },
          { header: "Região", content: invitation.region.name },
          { header: "Indicação", content: invitation.referral.name },
          { header: "Status", content: ap.status, id: "status-#{ap.id}", class: helpers.status_class(ap) },          
          { header: "Nº de Comparecimentos", content: lead.appointments.count },
          { header: "Ação", content: set_appointment_button(ap), id: "set-attendance-button-#{ap.id}", class: "pt-2 pb-0" },          
          { header: "Observações", content: invitation.notes },
          { header: "Mensagem", content: generate_message_content(lead, ap), id: "whatsapp-link-#{lead.id}" },
          { header: "Remarcação", content: reschedule_form(new_appointment, ap), class: "text-orange-500" },
          { header: "Cancelar?", content: set_cancel_button(ap), id: "cancel-attendance-button-#{ap.id}", class: "pt-2 pb-0" },
          { header: "Tornar cliente", content: set_conversion_link(lead), class: "text-purple-500" }
        ]                 
      end
    end  

    def set_conversion_link(lead)
       if lead.leads_conversion.present?
         helpers.link_to("Página do cliente", main_app.customer_orders_path(lead.customer), class: "text-blue-500 hover:text-blue-800 underline")
       else
         helpers.link_to("Converter para cliente", main_app.new_conversion_path(lead_id: lead.id), class: "text-red-500 hover:text-red-800 underline")
       end
    end
  
    def reschedule_form(new_appointment, old_appointment)
      if old_appointment.status != "remarcado"
        render_to_string(
          partial: "clinic_management/appointments/update_service_form",
          locals: { new_appointment: new_appointment, old_appointment: old_appointment, available_services: available_services(old_appointment.service) }
        )
      else
        ""
      end
    end

    def available_services(exception_service)
      exception_service_id = exception_service.id # Get the ID of the exception_service object
      ClinicManagement::Service.where("date >= ? AND id != ?", Date.today, exception_service_id)
    end

    def generate_message_content(lead, appointment)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: lead, appointment: appointment }
      )
    end

    def process_services_data(services)
      services.map.with_index do |ser, index|
        total_appointments, scheduled, rescheduled, canceleds = appointment_counts(ser)
        link = action_name == 'index_by_referral' ? show_by_referral_services_path(referral_id: @referral.id, id: ser.id) : ser
        [
          { header: "#", content: index + 1 },
          { header: "Data", content: helpers.link_to(ser.date.strftime("%d/%m/%Y"), link, class: "text-blue-500 hover:text-blue-700") },
          { header: "Dia da semana", content: helpers.show_week_day(ser.weekday) },
          { header: "Início", content: ser.start_time.strftime("%H:%M") },
          { header: "Fim", content: ser.end_time.strftime("%H:%M") },
          { header: "Pacientes", content: total_appointments },
          { header: "Compareceram", content: scheduled, class: "text-blue-700" },
          { header: "Remarcados", content:rescheduled, class: "text-green-700"  },
          { header: "Cancelados", content: canceleds, class: "text-red-600"  }
          # percentage_content("Presentes", scheduled, total_appointments, "text-blue-700", "bg-blue-200"),
          # percentage_content("Remarcados", rescheduled, total_appointments, "text-green-600", "bg-green-200"),
          # percentage_content("Cancelados", canceleds, total_appointments, "text-red-600", "bg-red-200")        
        ]
      end
    end
    

    def set_appointment_button(ap)
      if ap.attendance.present? || ap.status == "remarcado" || ap.service.date > Date.today
        "--"
      else
        helpers.button_to('Marcar como presente', set_attendance_appointment_path(ap), method: :patch, remote: true, class: "py-2 px-4 bg-blue-500 text-white rounded hover:bg-blue-700")
      end
    end

    def appointment_counts(service)
      p "###### params: " + params
      p "###### check referral data: " + @referral.id.to_s
      appointments = service.appointments.to_a
      if action_name == "index_by_referral"
        appointments.select! { |a| a.invitation.referral == @referral }
      end
      total_appointments = appointments.count
      scheduled = appointments.select { |a| a.attendance == true }.count
      rescheduled = appointments.select { |a| a.status == "remarcado" }.count
      canceleds = appointments.select { |a| a.status == "cancelado" }.count
    
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
      if ap.status == "agendado"
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
        params.require(:service).permit(:weekday, :start_time, :end_time, :date)
      end
  end
end
