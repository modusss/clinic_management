module ClinicManagement
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[ show edit update destroy ]
    skip_before_action :redirect_referral_users, only: [:index_by_referral, :show_by_referral]
    before_action :set_view_type, only: [:index_by_referral, :show_by_referral, :index, :show]
    include TimeSlotsHelper, GeneralHelper, PrescriptionsHelper

    require 'cgi'

    # GET /services
    def index
      @referrals = Referral.all
      @view_type = params[:view_type] || 'daily'
      @services = ClinicManagement::Service.includes(:appointments).order(date: :desc)
      
      # Filtrar serviços para auxiliares de clínica
      if helpers.clinical_assistant?(current_user)
        @services = @services.where("date >= ?", Date.current)
      end
      
      case @view_type
      when 'weekly'
        @rows = process_weekly_data(@services)
        @chart_data = generate_weekly_chart_data(@services)
      when 'monthly'
        @rows = process_monthly_data(@services)
        @chart_data = generate_monthly_chart_data(@services)
      else # daily
        @services = @services.page(params[:page]).per(20)
        @rows = process_services_data(@services)
      end
    end

    def index_by_referral
      @referral = Referral.find(params[:referral_id])
      @view_type = params[:view_type] || 'daily'
      @services = Service.joins(:appointments)
                          .where(appointments: { referral_code: @referral.code })
                          .order(date: :desc)
                          .distinct
      
      case @view_type
      when 'weekly'
        @rows = process_weekly_data_by_referral(@services)
        @chart_data = generate_weekly_chart_data_by_referral(@services)
      when 'monthly'
        @rows = process_monthly_data_by_referral(@services)
        @chart_data = generate_monthly_chart_data_by_referral(@services)
      else # daily
        @services = @services.page(params[:page]).per(20)
        @rows = process_services_data(@services)
      end
    end
    
    # GET /services/1
    def show
      @rows = process_appointments_data(@service.appointments) 
    end

    def search_appointment
      if params[:q].present?
      service = Service.find(params[:service_id])
      appointments = service.appointments
      # find the appointments with the given patient_name on params[:q]
      @appointments = appointments.select { |appointment| appointment.invitation.patient_name.downcase.include?(params[:q].downcase) }
      # display via turbo_stream a tabel of results on div id #appointment-results
        @rows = process_appointments_data(@appointments)
      else
        @rows = "" 
      end
      respond_to do |format|
        format.turbo_stream do
            render turbo_stream: 
                  turbo_stream.update("appointments-results", 
                                      helpers.data_table(@rows, 3))
        end
      end
    end

    def show_by_referral
      @referral = Referral.find(params[:referral_id])
      all_appointments = Appointment.where(referral_code: @referral.code)
      all_services = all_appointments.map(&:service).uniq
      all_services = all_services.sort_by { |service| service.date }.reverse
      @service = all_services.find { |s| s.id == params[:id].to_i }
      @rows = process_appointments_by_referral_data(@service.appointments)
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
      @services = []
      
      (params[:time_slots_dates] || []).each do |time_slot_date|
        data = JSON.parse(time_slot_date)
        time_slot = ClinicManagement::TimeSlot.find(data["time_slot_id"])
        date = Date.parse(data["date"])
        
        service = ClinicManagement::Service.new(service_params)
        service.weekday = time_slot.weekday
        service.start_time = time_slot.start_time
        service.end_time = time_slot.end_time
        service.date = date
        @services << service
      end

      if @services.any? && @services.all?(&:valid?) && @services.each(&:save)
        redirect_to services_path, notice: "Atendimentos criados com sucesso!"
      else
        @service = ClinicManagement::Service.new # for form rendering
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

    # PATCH /services/1/cancel
    def cancel
      @service = Service.find(params[:id])
      if @service.update(canceled: true)
        @service.appointments.each do |appointment|
          appointment.update(status: "cancelado")
        end
        redirect_to @service, notice: "Service was successfully canceled."
      else
        redirect_to @service, alert: "Failed to cancel the service."
      end
    end

    private

    def set_view_type
      @view_type = mobile_device? ? 'cards' : (params[:view_type] || cookies[:preferred_service_view] || 'table')
    end

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
      sorted_appointments = appointments.select { |appointment| appointment.referral_code == @referral.code }
      sorted_appointments.map.with_index(1) do |ap, index|
        lead = ap&.lead
        lead_phone = add_phone_mask(lead.phone)
        new_appointment = ClinicManagement::Appointment.new
        invitation = ap&.invitation
        next unless (invitation.present?) && (lead.present?) && (ap.present?) && (lead.name.present?) 
    
        if (invitation.present?) && (lead.present?)
          [
            { header: "#", content: index },
            {
              header: "Paciente", 
              content: render_to_string(
                partial: "clinic_management/leads/patient_name_with_edit_button", 
                locals: { invitation: ap.invitation }
              ).html_safe, 
              class: "nowrap size_20 patient-name"
            },   
            { header: "Comparecimento", content: ap.attendance ? "Sim" : "Não", id: "attendance-#{ap.id}", class: helpers.attendance_class(ap) },          
            { header: "Observações", content: ap.comments },
            { header: "Responsável", content: ((lead.name == invitation&.patient_name) ? "" : lead.name) },
            {  
              header: "Telefone", 
              content: render_to_string(
                partial: "clinic_management/leads/phone_with_message_tracking", 
                locals: { lead: lead, appointment: ap }
              ).html_safe,
              class: "text-blue-500 hover:text-blue-700 nowrap"
            },
            { header: "Remarcação", content: reschedule_form(new_appointment, ap), class: "text-orange-500" },
            { header: "Mensagem", content: generate_message_content(lead, ap), id: "whatsapp-link-#{lead.id.to_s}" },
            { header: "Endereço", content: invitation&.lead&.address },
            { header: "Região", content: invitation&.region&.name },
            { header: "Localização", content: get_location_link(lead) },
            { header: "Status", content: ap.status, id: "status-#{ap.id}", class: helpers.status_class(ap) }          
          ]
        end
      end
    end
    

    def get_location_link(lead)
      if lead.latitude.present? && lead.longitude.present?
        "<a target='_blank' href='https://www.google.com/maps/search/?api=1&query=#{lead.latitude},#{lead.longitude}'>Ver localização</a>".html_safe
      else
        ""
      end
    end

    def set_zap_message(service, invitation)
      if service.present? && invitation.present?
        message = "Oi #{invitation.patient_name.split.first}, tudo bem por aí?\n\nAqui é a #{invitation.referral.name}. Percebi que você não pôde chegar naquele exame de vista que combinamos pra #{I18n.l(service.date, format: "%A, %d/%m")} — tá tudo certo?\n\nSe rolou algum imprevisto, me conta, sem pressa. A gente pode tentar remarcar pra um horário que fique melhor pra você.\n\nQuero só garantir que você consiga cuidar direitinho da sua visão, sabe? 😌👓\n\nMe dá um toque quando puder, vou ficar aguardando sua resposta, tá bom?\n\nObrigada!"
        URI.encode_www_form_component(message)
      else
        ""
      end
    end

    def process_appointments_data(appointments)
      sorted_appointments = appointments.select { |ap| ap&.invitation&.patient_name.present? }
                                      .sort_by { |ap| ap.invitation.patient_name }
      sorted_appointments.map.with_index(1) do |ap, index|
        new_appointment = ClinicManagement::Appointment.new
        lead = ap&.lead
        lead_phone = add_phone_mask(lead.phone)
        invitation = ap&.invitation
        next unless (invitation.present?) && (lead.present?) && (ap.present?) && (lead.name.present?) 

        if (invitation.present?) && (lead.present?)
          [
            { header: "#", content: index },
            {
              header: "Paciente", 
              content: render_to_string(
                partial: "clinic_management/leads/patient_name_with_edit_button", 
                locals: { invitation: ap.invitation }
              ).html_safe, 
              class: "nowrap size_20 patient-name"
            },   
            { header: "Status", content: helpers.format_status_and_attendance(ap), id: "status-#{ap.id}", class: helpers.status_class(ap) },          
            { header: "Confirmado", content: render_to_string(
              partial: 'confirmation_toggle',
              locals: { appointment: ap }
            )},
            {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: ap, message: "" }), id: "appointment-comments-#{ap.id}"},
            { header: "Ação", content: set_appointment_button(ap), id: "set-attendance-button-#{ap.id}", class: "pt-2 pb-0" },          
            { header: "Tornar cliente", content: set_conversion_link(lead), class: "text-purple-500 nowrap" },
            { header: "Responsável", content: ((lead.name == invitation.patient_name) ? "" : lead.name), class: "nowrap" },
            {  
              header: "Telefone", 
              content: render_to_string(
                partial: "clinic_management/leads/phone_with_message_tracking", 
                locals: { lead: lead, appointment: ap }
              ).html_safe,
              class: "text-blue-500 hover:text-blue-700 nowrap"
            },
            { header: "Endereço", content: invitation.lead.address },
            { header: "Região", content: invitation.region.name.upcase },
            { header: "Localização", content: get_location_link(lead) },
            { header: "Indicação", content: invitation.referral.name.upcase },
            { header: "Nº de Comparecimentos", content: lead.appointments.count },
            { header: "Mensagem", content: generate_message_content(lead, ap), id: "whatsapp-link-#{lead.id.to_s}" },
            { header: "Mensagens enviadas:", content: ap.messages_sent&.join(', '), id: "messages-sent-#{ap.id.to_s}" },
            { header: "Remarcação", content: reschedule_form(new_appointment, ap), class: "text-orange-500" },
            { header: "Cancelar?", content: set_cancel_button(ap), id: "cancel-attendance-button-#{ap.id}", class: "pt-2 pb-0" }
          ]
        end                 
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

    def generate_message_content(lead, appointment)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: lead, appointment: appointment }
      )
    end

    def process_services_data(services)
      services.map.with_index do |ser, index|
        # Pular serviços passados para auxiliares de clínica
        next if helpers.clinical_assistant?(current_user) && ser.date < Date.current

        total_appointments, scheduled, rescheduled, canceleds = appointment_counts(ser)
        link = action_name == 'index_by_referral' ? show_by_referral_services_path(referral_id: @referral.id, id: ser.id) : ser
        
        # Determine the date status
        date_status = case
                      when ser.date < Date.current
                        "past"
                      when ser.date == Date.current
                        "today"
                      else
                        "future"
                      end
        service_name = ser&.service_type&.name
        if ser.canceled
          service_name = "#{service_name} <p style='color: red;'>(cancelado)</p>".html_safe
        end
        row = [
          { header: "Serviço", content: service_name },
          { header: "Data", content: helpers.link_to(ser.date.strftime("%d/%m/%Y"), link, class: "text-blue-500 hover:text-blue-700") },
          { header: "Dia da semana", content: helpers.show_week_day(ser.weekday) },
          { header: "Início", content: ser.start_time.strftime("%H:%M") },
          { header: "Fim", content: ser.end_time.strftime("%H:%M") },
          { header: "Pacientes", content: total_appointments },
          { header: "Compareceram", content: scheduled, class: "text-blue-700" },
          { header: "Remarcados", content: rescheduled, class: "text-green-700" },
          { header: "Cancelados", content: canceleds, class: "text-red-600" }
        ]
        if helpers.is_manager_above?
          row << { header: "Ação", content: should_edit_service?(ser) }
        end

        # Add row_class and row_id to the first cell of each row
        row.first[:row_class] = "service-row service-#{date_status}"
        row.first[:row_id] = "service-#{ser.id}"

        row
      end.compact # Remove nil entries (skipped services)
    end
    
    def should_edit_service?(service)
      service.date >= Date.current ? helpers.link_to("Editar", edit_service_path(service), class: "text-blue-500 hover:text-blue-700") : "--"
    end

    def set_appointment_button(ap)
      if ap.attendance.present? || ap.status == "remarcado" || ap.service.date > Date.current
        "--"
      else
        helpers.button_to('Marcar como presente', set_attendance_appointment_path(ap), method: :patch, remote: true, class: "py-2 px-4 bg-blue-500 text-white rounded hover:bg-blue-700")
      end
    end

    def appointment_counts(service)
      appointments = service.appointments.to_a
      if action_name == "index_by_referral"
        appointments.select! { |a| a&.invitation&.referral == @referral }
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

    def process_weekly_data(services)
      # Group services by week
      weekly_groups = services.group_by { |service| service.date.beginning_of_week }
      
      weekly_groups.map do |week_start, week_services|
        week_end = week_start.end_of_week
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        week_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        [
          { header: "Período", content: "#{week_start.strftime('%d/%m/%Y')} - #{week_end.strftime('%d/%m/%Y')}" },
          { header: "Serviços", content: week_services.count },
          { header: "Total de Pacientes", content: total_appointments },
          { header: "Compareceram", content: total_scheduled, class: "text-blue-700" },
          { header: "Remarcados", content: total_rescheduled, class: "text-green-700" },
          { header: "Cancelados", content: total_canceled, class: "text-red-600" },
          { header: "Taxa de Comparecimento", content: total_appointments > 0 ? "#{percentage(total_scheduled, total_appointments)}%" : "0%", class: "text-blue-700" }
        ]
      end
    end

    def process_monthly_data(services)
      # Group services by month
      monthly_groups = services.group_by { |service| service.date.beginning_of_month }
      
      monthly_groups.map do |month_start, month_services|
        month_end = month_start.end_of_month
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        month_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        [
          { header: "Mês", content: I18n.l(month_start, format: "%B de %Y").capitalize },
          { header: "Serviços", content: month_services.count },
          { header: "Total de Pacientes", content: total_appointments },
          { header: "Compareceram", content: total_scheduled, class: "text-blue-700" },
          { header: "Remarcados", content: total_rescheduled, class: "text-green-700" },
          { header: "Cancelados", content: total_canceled, class: "text-red-600" },
          { header: "Taxa de Comparecimento", content: total_appointments > 0 ? "#{percentage(total_scheduled, total_appointments)}%" : "0%", class: "text-blue-700" }
        ]
      end
    end

    def generate_weekly_chart_data(services)
      weekly_groups = services.group_by { |service| service.date.beginning_of_week }
      
      labels = []
      appointments_data = []
      scheduled_data = []
      rescheduled_data = []
      canceled_data = []
      
      weekly_groups.each do |week_start, week_services|
        week_end = week_start.end_of_week
        labels << "#{week_start.strftime('%d/%m')} - #{week_end.strftime('%d/%m')}"
        
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        week_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        appointments_data << total_appointments
        scheduled_data << total_scheduled
        rescheduled_data << total_rescheduled
        canceled_data << total_canceled
      end
      
      {
        labels: labels,
        datasets: [
          {
            label: 'Total de Pacientes',
            data: appointments_data,
            backgroundColor: 'rgba(59, 130, 246, 0.5)',
            borderColor: 'rgb(59, 130, 246)',
            borderWidth: 2
          },
          {
            label: 'Compareceram',
            data: scheduled_data,
            backgroundColor: 'rgba(34, 197, 94, 0.5)',
            borderColor: 'rgb(34, 197, 94)',
            borderWidth: 2
          },
          {
            label: 'Remarcados',
            data: rescheduled_data,
            backgroundColor: 'rgba(251, 191, 36, 0.5)',
            borderColor: 'rgb(251, 191, 36)',
            borderWidth: 2
          },
          {
            label: 'Cancelados',
            data: canceled_data,
            backgroundColor: 'rgba(239, 68, 68, 0.5)',
            borderColor: 'rgb(239, 68, 68)',
            borderWidth: 2
          }
        ]
      }
    end

    def generate_monthly_chart_data(services)
      monthly_groups = services.group_by { |service| service.date.beginning_of_month }
      
      labels = []
      appointments_data = []
      scheduled_data = []
      rescheduled_data = []
      canceled_data = []
      
      monthly_groups.each do |month_start, month_services|
        labels << I18n.l(month_start, format: "%B %Y").capitalize
        
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        month_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        appointments_data << total_appointments
        scheduled_data << total_scheduled
        rescheduled_data << total_rescheduled
        canceled_data << total_canceled
      end
      
      {
        labels: labels,
        datasets: [
          {
            label: 'Total de Pacientes',
            data: appointments_data,
            backgroundColor: 'rgba(59, 130, 246, 0.5)',
            borderColor: 'rgb(59, 130, 246)',
            borderWidth: 2
          },
          {
            label: 'Compareceram',
            data: scheduled_data,
            backgroundColor: 'rgba(34, 197, 94, 0.5)',
            borderColor: 'rgb(34, 197, 94)',
            borderWidth: 2
          },
          {
            label: 'Remarcados',
            data: rescheduled_data,
            backgroundColor: 'rgba(251, 191, 36, 0.5)',
            borderColor: 'rgb(251, 191, 36)',
            borderWidth: 2
          },
          {
            label: 'Cancelados',
            data: canceled_data,
            backgroundColor: 'rgba(239, 68, 68, 0.5)',
            borderColor: 'rgb(239, 68, 68)',
            borderWidth: 2
          }
        ]
      }
    end

    def process_weekly_data_by_referral(services)
      weekly_groups = services.group_by { |service| service.date.beginning_of_week }
      
      weekly_groups.map do |week_start, week_services|
        week_end = week_start.end_of_week
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        week_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        [
          { header: "Período", content: "#{week_start.strftime('%d/%m/%Y')} - #{week_end.strftime('%d/%m/%Y')}" },
          { header: "Serviços", content: week_services.count },
          { header: "Total de Pacientes", content: total_appointments },
          { header: "Compareceram", content: total_scheduled, class: "text-blue-700" },
          { header: "Remarcados", content: total_rescheduled, class: "text-green-700" },
          { header: "Cancelados", content: total_canceled, class: "text-red-600" },
          { header: "Taxa de Comparecimento", content: total_appointments > 0 ? "#{percentage(total_scheduled, total_appointments)}%" : "0%", class: "text-blue-700" }
        ]
      end
    end

    def process_monthly_data_by_referral(services)
      monthly_groups = services.group_by { |service| service.date.beginning_of_month }
      
      monthly_groups.map do |month_start, month_services|
        month_end = month_start.end_of_month
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        month_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        [
          { header: "Mês", content: I18n.l(month_start, format: "%B de %Y").capitalize },
          { header: "Serviços", content: month_services.count },
          { header: "Total de Pacientes", content: total_appointments },
          { header: "Compareceram", content: total_scheduled, class: "text-blue-700" },
          { header: "Remarcados", content: total_rescheduled, class: "text-green-700" },
          { header: "Cancelados", content: total_canceled, class: "text-red-600" },
          { header: "Taxa de Comparecimento", content: total_appointments > 0 ? "#{percentage(total_scheduled, total_appointments)}%" : "0%", class: "text-blue-700" }
        ]
      end
    end

    def generate_weekly_chart_data_by_referral(services)
      weekly_groups = services.group_by { |service| service.date.beginning_of_week }
      
      labels = []
      appointments_data = []
      scheduled_data = []
      rescheduled_data = []
      canceled_data = []
      
      weekly_groups.each do |week_start, week_services|
        week_end = week_start.end_of_week
        labels << "#{week_start.strftime('%d/%m')} - #{week_end.strftime('%d/%m')}"
        
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        week_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        appointments_data << total_appointments
        scheduled_data << total_scheduled
        rescheduled_data << total_rescheduled
        canceled_data << total_canceled
      end
      
      {
        labels: labels,
        datasets: [
          {
            label: 'Total de Pacientes',
            data: appointments_data,
            backgroundColor: 'rgba(59, 130, 246, 0.5)',
            borderColor: 'rgb(59, 130, 246)',
            borderWidth: 2
          },
          {
            label: 'Compareceram',
            data: scheduled_data,
            backgroundColor: 'rgba(34, 197, 94, 0.5)',
            borderColor: 'rgb(34, 197, 94)',
            borderWidth: 2
          },
          {
            label: 'Remarcados',
            data: rescheduled_data,
            backgroundColor: 'rgba(251, 191, 36, 0.5)',
            borderColor: 'rgb(251, 191, 36)',
            borderWidth: 2
          },
          {
            label: 'Cancelados',
            data: canceled_data,
            backgroundColor: 'rgba(239, 68, 68, 0.5)',
            borderColor: 'rgb(239, 68, 68)',
            borderWidth: 2
          }
        ]
      }
    end

    def generate_monthly_chart_data_by_referral(services)
      monthly_groups = services.group_by { |service| service.date.beginning_of_month }
      
      labels = []
      appointments_data = []
      scheduled_data = []
      rescheduled_data = []
      canceled_data = []
      
      monthly_groups.each do |month_start, month_services|
        labels << I18n.l(month_start, format: "%B %Y").capitalize
        
        total_appointments = 0
        total_scheduled = 0
        total_rescheduled = 0
        total_canceled = 0
        
        month_services.each do |service|
          appointments, scheduled, rescheduled, canceled = appointment_counts(service)
          total_appointments += appointments
          total_scheduled += scheduled
          total_rescheduled += rescheduled
          total_canceled += canceled
        end
        
        appointments_data << total_appointments
        scheduled_data << total_scheduled
        rescheduled_data << total_rescheduled
        canceled_data << total_canceled
      end
      
      {
        labels: labels,
        datasets: [
          {
            label: 'Total de Pacientes',
            data: appointments_data,
            backgroundColor: 'rgba(59, 130, 246, 0.5)',
            borderColor: 'rgb(59, 130, 246)',
            borderWidth: 2
          },
          {
            label: 'Compareceram',
            data: scheduled_data,
            backgroundColor: 'rgba(34, 197, 94, 0.5)',
            borderColor: 'rgb(34, 197, 94)',
            borderWidth: 2
          },
          {
            label: 'Remarcados',
            data: rescheduled_data,
            backgroundColor: 'rgba(251, 191, 36, 0.5)',
            borderColor: 'rgb(251, 191, 36)',
            borderWidth: 2
          },
          {
            label: 'Cancelados',
            data: canceled_data,
            backgroundColor: 'rgba(239, 68, 68, 0.5)',
            borderColor: 'rgb(239, 68, 68)',
            borderWidth: 2
          }
        ]
      }
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
        params.require(:service).permit(:service_type_id)
      end
  end
end
