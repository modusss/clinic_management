module ClinicManagement
  class LeadsController < ApplicationController
    before_action :set_lead, only: %i[ show edit update destroy ]
    before_action :set_menu, only: %i[ index absent attended cancelled ]
    before_action :set_referral, only: %i[ index absent attended cancelled ]
    skip_before_action :redirect_referral_users

    include GeneralHelper

    # GET /leads
    # def index
      # @leads = Lead.includes(:invitations, :appointments).page(params[:page]).per(50)
      # @rows = load_leads_data(@leads)
    # end
    
    # GET /leads/1
    def show
      @rows = get_lead_data
      @new_appointment = ClinicManagement::Appointment.new
      @old_appointment = @lead.appointments&.last
      if @old_appointment.present?
        @available_services = available_services(@old_appointment&.service)
      else
        @available_services = ClinicManagement::Service.where("date >= ?", Date.current)
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
      @leads = @leads.limit(30) unless @leads.blank?
      
      # Adicionar available_services para uso no partial
      @available_services = ClinicManagement::Service.where("date >= ?", Date.current).order(date: :asc)
      
      respond_to do |format|
        format.turbo_stream do
            render turbo_stream: 
                  turbo_stream.update("lead-results", 
                                      partial: "lead_results", 
                                      locals: { leads: @leads, available_services: @available_services })
        end
      end
    end

    def search_absents
      query = params[:q]&.strip
      if helpers.referral?(current_user)
        @all_leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', false, 120.days.ago)
      else
        @all_leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', false, 1.days.ago)
      end
      
      if query.present?
        @leads = @all_leads.where("name ILIKE ? OR phone ILIKE ?", "%#{query}%", "%#{query}%").limit(10)
      else
        @leads = @all_leads.page(params[:page]).per(50)
      end

      @rows = load_leads_data(@leads)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "table-tab",
            partial: "absent_table",
            locals: { rows: @rows, leads: @leads }
          )
        end
      end
    end

    def absent
      
      # Se chegamos aqui, ou não temos estado salvo ou já estamos com parâmetros
      # Salvar o estado atual na sessão (URL completa com parâmetros)
      session[:absent_leads_state] = request.original_url if request.get?
      
      # 1) Carregar a coleção base (com base se é referral ou não)
      if helpers.referral?(current_user)
        @all_leads = fetch_leads_by_appointment_condition(
          'clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', 
          false, 
          120.days.ago
        )
      else
        @all_leads = fetch_leads_by_appointment_condition(
          'clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', 
          false, 
          1.days.ago
        )
      end
    
      # 2) Se tiver Ano e Mês nos parâmetros, filtrar por esse intervalo
      if params[:year].present? && params[:month].present?
        start_date = Date.new(params[:year].to_i, params[:month].to_i, 1)
        end_date   = start_date.end_of_month
        
        # Corrigir a query para usar o mesmo join que já existe
        @all_leads = @all_leads.where('clinic_management_services.date BETWEEN ? AND ?', start_date, end_date)
      end
    
      # 3) Se tiver busca por nome/telefone, filtra adicionalmente
      query = params[:q]&.strip
      if query.present?
        @leads = @all_leads.where(
          "name ILIKE ? OR phone ILIKE ?", 
          "%#{query}%", 
          "%#{query}%"
        )
      else
        @leads = @all_leads
      end
    
      # 4) Paginação e montagem das linhas (caso não seja aba de download)
      if params[:tab] == 'download'
        @date_range = (Date.current - 1.year)..Date.current
      else
        @leads = @leads.page(params[:page]).per(50)
        @rows  = load_leads_data(@leads)
      end
    
      # 5) Responde renderizando :absent ou :absent_download conforme a aba
      respond_to do |format|
        format.html { render :absent }  # exibe a view normal
        format.html { render :absent_download if params[:view] == 'download' }
      end
    end
    

    def absent_download
      if helpers.referral?(current_user)
        @all_leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', false, 120.days.ago)
      else
        @all_leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', false, 1.days.ago)
      end

      if @all_leads.any?
        start_date = @all_leads.last.appointments.last.service.date
        end_date = @all_leads.first.appointments.last.service.date
        @date_range = (start_date.to_date..end_date.to_date).map(&:beginning_of_month).uniq.reverse
      else
        @date_range = []
      end

      render :absent_download
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
      @leads = fetch_leads_for_download
      @rows = load_leads_data_for_csv(@leads)

      respond_to do |format|
        format.csv { send_data generate_csv(@rows), filename: generate_filename }
      end
    end

    def record_message_sent
      @lead = Lead.find(params[:id])
      @appointment = Appointment.find(params[:appointment_id])
      
      # Log para depuração
      Rails.logger.info "Processing record_message_sent for lead #{@lead.id}"
      Rails.logger.info "Accept header: #{request.headers['Accept']}"
      
      # Update the appointment with the message tracking info
      @appointment.update(
        last_message_sent_at: Time.current,
        last_message_sent_by: current_user.name
      )
      
      # Renderizar a resposta Turbo Stream
      response.headers["Content-Type"] = "text/vnd.turbo-stream.html"
      
      # Renderizar os templates Turbo Stream
      phone_html = render_to_string(
        partial: "clinic_management/leads/phone_with_message_tracking", 
        locals: { lead: @lead, appointment: @appointment }
      )
      
      # Construir a resposta Turbo Stream manualmente
      turbo_stream_response = <<~HTML
        <turbo-stream action="replace" target="phone-container-#{@lead.id}">
          <template>
            #{phone_html}
          </template>
        </turbo-stream>
      HTML
      
      Rails.logger.info "Sending Turbo Stream response: #{turbo_stream_response.inspect}"
      
      render html: turbo_stream_response.html_safe
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
    

    def generate_message_content(lead, appointment)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: lead, appointment: appointment }
      )
    end

    def get_lead_data
      current_referral = helpers.user_referral if helpers.referral?(current_user)

      appointments = @lead.appointments.includes(:invitation, :service).order('clinic_management_services.date DESC')

      appointments.map.with_index do |ap, index|
        invitation = ap.invitation
        is_current_referral_invitation = current_referral && invitation.referral_id == current_referral.id
        new_appointment = ClinicManagement::Appointment.new

        service_content = if helpers.referral?(current_user)
                            if is_current_referral_invitation
                              helpers.link_to(invite_day(ap), clinic_management.show_by_referral_services_path(referral_id: current_referral.id, id: ap.service.id), class: "text-blue-500 hover:text-blue-700")
                            else
                              invite_day(ap)
                            end
                          else
                            helpers.link_to(invite_day(ap), clinic_management.service_path(ap.service), class: "text-blue-500 hover:text-blue-700")
                          end

        row = [
          {header: "#", content: index + 1},
          {
            header: "Paciente", 
            content: render_to_string(
              partial: "clinic_management/leads/patient_name_with_edit_button", 
              locals: { invitation: ap.invitation }
            ).html_safe, 
            class: "nowrap size_20"
          },          
          {header: "Data do atendimento", content: service_content},
          {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: ap, message: "" }), id: "appointment-comments-#{ap.id}"},                   
          {header: "Remarcação", content: reschedule_form(new_appointment, ap), class: "text-orange-500"},
          {header: "Comparecimento", content: (ap.attendance == true ? "Sim" : "Não"), class: helpers.attendance_class(ap)},
          {header: "Status", content: ap.status, class: helpers.status_class(ap)},
          {header: "Data do convite", content: invitation&.created_at&.strftime("%d/%m/%Y")},
          {header: "Região", content: invitation&.region&.name}
        ]

        unless helpers.referral?(current_user)
          row.insert(5, {header: "Receita", content: prescription_link(ap), class: "nowrap"})
          row << {header: "Convidado por", content: invitation&.referral&.name}
          row << {header: "Mensagem", content: generate_message_content(@lead, ap), id: "whatsapp-link-#{@lead.id}"}
        end

        row
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
      leads.map.with_index do |lead, index|
        last_invitation = lead.invitations.last
        last_appointment = lead.appointments.last
        if helpers.referral?(current_user)
          new_appointment = ClinicManagement::Appointment.new

          [
            {header: "Ordem", content: index + 1},
            {
              header: "Paciente", 
              content: render_to_string(
                partial: "clinic_management/leads/patient_name_with_edit_button", 
                locals: { invitation: last_invitation }
              ).html_safe, 
              class: "nowrap size_20"
            },   
            {header: "Responsável", content: responsible_content(last_invitation), class: "nowrap"},
            {
              header: "Telefone", 
              content: render_to_string(
                partial: "clinic_management/leads/phone_with_message_tracking", 
                locals: { lead: lead, appointment: last_appointment }
              ).html_safe, 
              class: "text-blue-500 hover:text-blue-700 nowrap"
            },
            {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: last_appointment, message: "" }), id: "appointment-comments-#{last_appointment.id}"},
            {header: "Vezes convidado", content: lead.invitations.count},
            {header: "Último atendimento", content: "#{invite_day(last_appointment)}"},
            {header: "Remarcação", content: reschedule_form(new_appointment, last_appointment), class: "text-orange-500" },
          ]
        else
          [
            {header: "Ordem", content: index + 1},
            {
              header: "Paciente", 
              content: render_to_string(
                partial: "clinic_management/leads/patient_name_with_edit_button", 
                locals: { invitation: last_invitation }
              ).html_safe, 
              class: "nowrap size_20"
            },   
            {header: "Responsável", content: responsible_content(last_invitation), class: "nowrap"},
            {
              header: "Telefone", 
              content: render_to_string(
                partial: "clinic_management/leads/phone_with_message_tracking", 
                locals: { lead: lead, appointment: last_appointment }
              ).html_safe, 
              class: "text-blue-500 hover:text-blue-700 nowrap"
            },
            {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: last_appointment, message: "" }), id: "appointment-comments-#{last_appointment.id}"},
            {header: "Último indicador", content: last_referral(last_invitation)},
            {header: "Qtd. de convites", content: lead.invitations.count},
            {header: "Qtd. de atendimentos", content: lead.appointments.count},
            {header: "Último atendimento", content: last_appointment_link(last_appointment)},
            {header: "Remarcação", content: reschedule_form(new_appointment, last_appointment), class: "text-orange-500" }
          ]
        end
      end
    end
    
    def reschedule_form(new_appointment, old_appointment)
      if old_appointment.status != "remarcado"
        render_to_string(
          partial: "clinic_management/appointments/update_service_form",
          locals: { 
            new_appointment: new_appointment, 
            old_appointment: old_appointment, 
            available_services: available_services(old_appointment.service) 
          }
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
        one_year_ago = Date.current - 1.year
      
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

      def appointment_params
        params.require(:clinic_management_appointment).permit(:comments)
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
            last_invitation.patient_name,
            responsible_content(last_invitation),
            add_phone_mask(lead.phone),
            last_appointment ? invite_day(last_appointment) : "",
            lead.appointments.count,
            "",
            ""
          ]
        end
      end

      def fetch_leads_for_download
        if helpers.referral?(current_user)
          leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', false, 120.days.ago)
        else
          leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ?', false)
        end
        
        if params[:year].present? && params[:month].present?
          start_date = Date.new(params[:year].to_i, params[:month].to_i, 1)
          end_date = start_date.end_of_month
          leads = leads.joins(appointments: :service)
                       .where('clinic_management_services.date BETWEEN ? AND ?', start_date, end_date)
        end

        leads
      end

      def generate_filename
        month_name = I18n.t("date.month_names")[params[:month].to_i]
        "leads_#{month_name.downcase}_#{params[:year]}.csv"
      end

      def available_services(service)
        # Implemente a lógica para obter os serviços disponíveis
        # Similar à implementação que você já tem no ServicesController
        Service.where("date >= ?", Date.current).order(date: :asc)
      end
  end
end