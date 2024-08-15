module ClinicManagement
  class LeadsController < ApplicationController
    before_action :set_lead, only: %i[ show edit update destroy ]
    before_action :set_menu, only: %i[ index absent attended cancelled ]
    before_action :set_referral, only: %i[ index absent attended cancelled ]
    skip_before_action :redirect_referral_users

    include GeneralHelper

    # GET /leads
    def index
      @leads = Lead.includes(:invitations, :appointments).page(params[:page]).per(50)
      @rows = load_leads_data(@leads)
    end
    
    # GET /leads/1
    def show
      @rows = get_lead_data
      @new_appointment = ClinicManagement::Appointment.new
      @old_appointment = @lead.appointments&.last
      if @old_appointment.present?
        @available_services = available_services(@old_appointment&.service)
      else
        @available_services = ClinicManagement::Service.where("date >= ?", Date.today)
      end
    end

    # GET /leads/new
    def new
      @lead = Lead.new
    end

    # GET /leads/1/edit
    def edit
    end

    # POST /leads
    def create
      @lead = Lead.new(lead_params)

      if @lead.save
        redirect_to @lead, notice: "Lead was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /leads/1
    def update
      if @lead.update(lead_params)
        redirect_to @lead, notice: "Lead was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /leads/1
    def destroy
      @lead.destroy
      if helpers.referral? current_user
        redirect_to new_invitation_path
      else
        # Use `fallback_location` to handle cases where the referrer is missing or invalid.
        redirect_to services_path
      end
    end

    def search
      params = request.params[:q]
      @leads = params.blank? ? [] : Lead.search_by_name_or_phone(params)   
      @leads = @leads.limit(10) unless @leads.blank?
      respond_to do |format|
        format.turbo_stream do
            render turbo_stream: 
                  turbo_stream.update("lead-results", 
                                      partial: "lead_results", 
                                      locals: { leads: @leads })
        end
      end
    end

    def absent
      @leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', false, 120.days.ago).page(params[:page]).per(50)
      @rows = load_leads_data(@leads)
      render :index
    end    
=begin
    def attended
      @leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ?', true).page(params[:page]).per(50)
      @rows = load_leads_data(@leads)
      render :index
    end
    
    def cancelled
      @leads = fetch_leads_by_appointment_condition('clinic_management_appointments.status = ?', 'cancelado').page(params[:page]).per(50)
      @rows = load_leads_data(@leads)
      render :index
    end
=end    

    def download_leads
      @leads = Lead.includes(:invitations, :appointments).page(params[:page]).per(50)
      @rows = load_leads_data_for_csv(@leads)

      respond_to do |format|
        format.csv { send_data generate_csv(@rows), filename: "leads-#{Date.today}.csv" }
      end
    end

    
    private

    def generate_csv(rows)
      CSV.generate(headers: true) do |csv|
        csv << ["Paciente", "Responsável", "Telefone", "Último atendimento", "Atendeu?", "Remarcado?", "Observações do contato"] # Cabeçalhos

        rows.each do |row|
          csv << [
            row[0],                          # Paciente
            row[1],                          # Responsável
            row[2],                          # Telefone
            row[3],                          # Último atendimento
            "",                               # Atendeu?
            "",                               # Remarcado?
            ""                                # Observações
          ]
        end
      end
    end

    def available_services(exception_service)
      exception_service_id = exception_service&.id # Get the ID of the exception_service object
      ClinicManagement::Service.where("date >= ?", Date.today).where.not(id: exception_service_id)
    end
    

    def generate_message_content(lead, appointment)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: lead, appointment: appointment }
      )
    end

    def get_lead_data
      @lead.appointments.map.with_index do |ap, index|
        invitation = ap.invitation
        [
          {header: "#", content: index + 1},
          {header: "Paciente", content: invitation&.patient_name },
          {header: "Data do atendimento", content: helpers.link_to(invite_day(ap), service_path(ap.service), class: "text-blue-500 hover:text-blue-700")},         
          {header: "Comparecimento", content: (ap.attendance == true ? "Sim" : "Não"), class: helpers.attendance_class(ap)},
          {header: "Receita", content: prescription_link(ap)},
          {header: "Status", content: ap.status, class: helpers.status_class(ap)},
          {header: "Data do convite", content: invitation&.created_at&.strftime("%d/%m/%Y")},
          {header: "Convidado por", content: invitation&.referral&.name},
          {header: "Região", content: invitation&.region&.name},
          {header: "Mensagem", content: generate_message_content(@lead, ap), id: "whatsapp-link-#{@lead.id}" }
        ]
      end
    end

    def set_menu
      @menu = [
        # {url_name: 'Todos', url: 'leads', controller_name: 'leads', action_name: 'index'},
        {url_name: 'Ausentes', url: 'absent_leads', controller_name: 'leads', action_name: 'absent'},
        {url_name: 'Compareceram', url: 'attended_leads', controller_name: 'leads', action_name: 'attended'},
        {url_name: 'Cancelados', url: 'cancelled_leads', controller_name: 'leads', action_name: 'cancelled'}
      ]
    end

    def load_leads_data(leads)
      # if helpers.referral?(current_user)
      #   leads = leads.joins(:invitations).where(invitations: { referral_id: current_user.id })
      # end
    
      leads.map.with_index do |lead, index|
        last_invitation = lead.invitations.last
        last_appointment = lead.appointments.last
        if helpers.referral?(current_user)
          
          new_appointment = ClinicManagement::Appointment.new

          [
            {header: "Ordem", content: index + 1},
            {header: "Paciente", content: lead.name, class: "text-blue"},
            {header: "Responsável", content: responsible_content(last_invitation)},
            {header: "Telefone", content: "<a target='_blank' href='#{helpers.whatsapp_link(lead.phone, "")}'>#{lead.phone}</a> <a href='tel:#{lead.phone}'><i class='fas fa-phone'></i></a>".html_safe, class: "text-blue-500 hover:text-blue-700" },
            {header: "Vezes convidado", content: lead.invitations.count},
            {header: "Último atendimento", content: "#{invite_day(last_appointment)}"},
            {header: "Remarcação", content: reschedule_form(new_appointment, last_appointment), class: "text-orange-500" }
          ]
        else
          [
            {header: "Ordem", content: index + 1},
            {header: "Paciente", content: helpers.link_to(lead.name, lead_path(lead), class: "text-blue-500 hover:text-blue-700", target: "_blank")},
            {header: "Responsável", content: responsible_content(last_invitation)},
            {header: "Telefone", content: "<a target='_blank' href='#{helpers.whatsapp_link(lead.phone, "")}'>#{lead.phone}</a> <a href='tel:#{lead.phone}'><i class='fas fa-phone'></i></a>".html_safe, class: "text-blue-500 hover:text-blue-700"},
            {header: "Último indicador", content: last_referral(last_invitation)},
            {header: "Qtd. de convites", content: lead.invitations.count},
            {header: "Qtd. de atendimentos", content: lead.appointments.count},
            {header: "Último atendimento", content: last_appointment_link(last_appointment)}# ,
            # {header: "Mensagem", content: generate_message_content(lead, last_appointment), id: "whatsapp-link-#{lead.id}" }
          ]
        end
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

    def last_referral(last_invitation)
      last_invitation&.referral&.name || ""
    end

    def last_appointment_link(last_appointment)
      last_appointment.present? ? helpers.link_to("#{invite_day(last_appointment)}", service_path(last_appointment.service), class: "text-blue-500 hover:text-blue-700", target: "_blank") : ""
    end
    
    
      def responsible_content(invite)
        if invite.present?
          (invite.lead.name != invite.patient_name) ? invite.lead.name : ""
        else
          ""
        end
      end

      def fetch_leads_by_appointment_condition(query_condition, value, date = nil)
        # Data de um ano atrás a partir de hoje
        one_year_ago = Date.today - 1.year
      
        # IDs dos leads que tiveram attendance como true dentro do último ano
        excluded_lead_ids = ClinicManagement::Appointment.joins(:service)
                                                         .where('clinic_management_appointments.attendance = ? AND clinic_management_services.date >= ?', true, one_year_ago)
                                                         .pluck(:lead_id)
      
        if date
          ClinicManagement::Lead.joins(appointments: :service)
                                .where(query_condition, value, date)
                                .where('last_appointment_id IN (?)', ClinicManagement::Appointment.joins(:service).where(query_condition, value, date).pluck(:id))
                                .where.not(id: excluded_lead_ids)
                                .order('clinic_management_services.date DESC')
        else
          ClinicManagement::Lead.joins(appointments: :service)
                                .where(id: ClinicManagement::Appointment.where(query_condition, value).select(:lead_id))
                                .where('last_appointment_id IN (?)', ClinicManagement::Appointment.where(query_condition, value).pluck(:id))
                                .where.not(id: excluded_lead_ids)
                                .order('clinic_management_services.date DESC')
        end
      end
        
      # Use callbacks to share common setup or constraints between actions.
      def set_lead
        @lead = Lead.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def lead_params
        params.require(:lead).permit(:name, :phone, :address, :converted, :latitude, :longitude)
      end

      def prescription_link(ap)
        if ap.prescription.present?
          helpers.link_to("Ver receita", appointment_prescription_path(ap), class: "text-white bg-indigo-500 hover:bg-indigo-600 px-4 py-2 rounded")
        else
          helpers.link_to("Lançar receita", new_appointment_prescription_path(ap), class: "bg-blue-600 hover:bg-blue-800 text-white py-2 px-4 rounded")
        end
      end

      def load_leads_data_for_csv(leads)
        leads.map.with_index do |lead, index|
          last_invitation = lead.invitations.last
          last_appointment = lead.appointments.last

          [
            lead.name,
            responsible_content(last_invitation),
            add_phone_mask(lead.phone),
            last_appointment ? invite_day(last_appointment) : "",
            lead.appointments.count,
            "",
            ""
          ]
        end
      end
  end
end