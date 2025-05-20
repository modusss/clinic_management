module ClinicManagement
  class LeadsController < ApplicationController
    before_action :set_lead, only: %i[ show edit update destroy ]
    before_action :set_menu, only: %i[ index absent attended cancelled ]
    before_action :set_referral, only: %i[ index absent attended cancelled ]
    skip_before_action :redirect_referral_users
    before_action :set_view_type, only: [:absent]

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
      @leads = @leads.limit(10) unless @leads.blank?
      
      # Adicionar available_services para uso no partial
      @available_services = ClinicManagement::Service.where("date >= ?", Date.current).order(date: :asc)
      
      # Pré-carregar os dados necessários para cada lead
      unless @leads.blank?
        local_referral = Referral.find_by(name: 'Local')
        
        @leads = @leads.map do |lead|
          # Buscar o último appointment do lead
          last_appointment = lead.appointments.includes(:service, invitation: :referral).order('clinic_management_services.date DESC').first
          
          # Determinar o referral_id padrão para pré-seleção
          default_referral_id = nil
          
          if last_appointment && 
             last_appointment.service && 
             last_appointment.service.date > 1.year.ago &&
             last_appointment.invitation && 
             last_appointment.invitation.referral
            # Se o último appointment foi há menos de um ano, use o referral dele
            default_referral_id = last_appointment.invitation.referral_id
          else
            # Caso contrário, use 'Local'
            default_referral_id = local_referral&.id
          end
          
          # Adicionar os atributos ao lead
          lead.instance_variable_set(:@last_appointment, last_appointment)
          lead.instance_variable_set(:@default_referral_id, default_referral_id)
          
          # Definir métodos de acesso para esses atributos
          lead.singleton_class.class_eval do
            attr_reader :last_appointment, :default_referral_id
          end
          
          lead
        end
      end
      
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

      # Store the URL, potentially modified, in the session on GET requests
      if request.get?
        # Parse the original URL
        uri = URI.parse(request.original_url)
        # Parse the query string into a hash (handle cases with no query)
        params_hash = Rack::Utils.parse_nested_query(uri.query || "")

        # Check if the specific condition is met (viewing 'not_contacted' leads)
        if params_hash['contact_status'] == 'not_contacted'
          # Remove the 'page' parameter if it exists
          params_hash.delete('page')
          # Rebuild the query string from the modified hash. Use .presence to make it nil if empty.
          uri.query = Rack::Utils.build_query(params_hash).presence
          # Store the modified URL string
          session[:absent_leads_state] = uri.to_s
        else
          # Otherwise, store the original URL
          session[:absent_leads_state] = request.original_url
        end
      end
      
      # 1) Carregar a coleção base (com base se é referral ou não)
      one_year_ago = 1.year.ago.to_date
      absent_threshold_date = helpers.referral?(current_user) ? 120.days.ago.to_date : 1.day.ago.to_date
      
      if helpers.referral?(current_user)
        @all_leads = fetch_leads_by_appointment_condition(
          'clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', 
          false, 
          absent_threshold_date
        )
      else
        @all_leads = fetch_leads_by_appointment_condition(
          'clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', 
          false, 
          absent_threshold_date
        )
      end

      # Filter out leads without a phone number
      @all_leads = @all_leads.where.not(phone: [nil, ''])

      # 1.5) Apply patient type filter if specified
      if params[:patient_type].present? && params[:patient_type] != "all"
        case params[:patient_type]
        when "absent"
          # Only include leads whose last appointment was missed (attendance = false)
          @all_leads = @all_leads.where('clinic_management_appointments.attendance = ?', false)
        when "attended_year_ago"
          # Only include leads whose last appointment was attended but more than a year ago
          @all_leads = @all_leads.where('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', true, one_year_ago)
        end
      end

      # 2) Aplicar filtro de data apenas se ano E mês estiverem presentes
      if params[:year].present? && params[:month].present?
        start_date = Date.new(params[:year].to_i, params[:month].to_i, 1)
        end_date = start_date.end_of_month
        
        # Filtrar por período de data
        @all_leads = @all_leads.where('clinic_management_services.date BETWEEN ? AND ?', start_date, end_date)
      elsif params[:year].present? # Se só o ano estiver presente
        start_date = Date.new(params[:year].to_i, 1, 1)
        end_date = Date.new(params[:year].to_i, 12, 31)
        
        # Filtrar apenas pelo ano
        @all_leads = @all_leads.where('clinic_management_services.date BETWEEN ? AND ?', start_date, end_date)
      end
      # Se só o mês estiver presente ou nenhum dos dois, não aplicamos filtro de data

      # 3) Aplicar filtro de status de contato
      if params[:contact_status].present? && params[:contact_status] != "all"
        case params[:contact_status]
        when "not_contacted"
          # Filtrar apenas leads onde TODOS os appointments não têm mensagens
          contacted_lead_ids = ClinicManagement::Appointment
                                .where('last_message_sent_at IS NOT NULL')
                                .distinct
                                .pluck(:lead_id)
          @all_leads = @all_leads.where.not(id: contacted_lead_ids)
        when "contacted"
          # Filtrar apenas leads com pelo menos um appointment com mensagem
          contacted_lead_ids = ClinicManagement::Appointment
                                .where('last_message_sent_at IS NOT NULL')
                                .distinct
                                .pluck(:lead_id)
          @all_leads = @all_leads.where(id: contacted_lead_ids)
        when "contacted_by_me"
          # Filtrar apenas leads com mensagens enviadas pelo usuário atual
          contacted_by_me_lead_ids = ClinicManagement::Appointment
                                        .where('last_message_sent_at IS NOT NULL')
                                        .where('last_message_sent_by = ?', current_user.name)
                                        .distinct
                                        .pluck(:lead_id)
          @all_leads = @all_leads.where(id: contacted_by_me_lead_ids)
        end
      end

      # 4) Aplicar ordenação independentemente dos outros filtros
      @all_leads = @all_leads.joins("INNER JOIN clinic_management_appointments ON clinic_management_appointments.id = clinic_management_leads.last_appointment_id")
                             .joins("INNER JOIN clinic_management_services ON clinic_management_services.id = clinic_management_appointments.service_id")
      
      # Determine the sort order, defaulting to newest appointment first
      sort_order = params[:sort_order] || 'appointment_newest_first' 
      
      case sort_order
      when "appointment_newest_first"
        # Sort by the service date of the last appointment (most recent first)
        @all_leads = @all_leads.order('clinic_management_services.date DESC')
      when "appointment_oldest_first"
         # Sort by the service date of the last appointment (oldest first)
        @all_leads = @all_leads.order('clinic_management_services.date ASC')
      when "contact_newest_first"
        # Sort by the last contact time (most recent first), putting never contacted leads last
        @all_leads = @all_leads.order(Arel.sql('clinic_management_appointments.last_message_sent_at DESC NULLS LAST'))
      when "contact_oldest_first"
        # Sort by the last contact time (oldest first), putting never contacted leads last
        @all_leads = @all_leads.order(Arel.sql('clinic_management_appointments.last_message_sent_at ASC NULLS LAST'))
      else
        # Default fallback sort order
        @all_leads = @all_leads.order('clinic_management_services.date DESC')
      end

      # 5) Se tiver busca por nome/telefone, filtra adicionalmente
      query = params[:q]&.strip
      if query.present?
        @leads = @all_leads.where(
          "clinic_management_leads.name ILIKE ? OR clinic_management_leads.phone ILIKE ?", 
          "%#{query}%", 
          "%#{query}%"
        )
      else
        @leads = @all_leads
      end

      # 6) Paginação e montagem das linhas
      if params[:tab] == 'download'
        @date_range = (Date.current - 1.year)..Date.current
      else
        @leads = @leads.page(params[:page]).per(50)
        @rows = load_leads_data(@leads)
      end

      # 7) Responde renderizando :absent ou :absent_download conforme a aba
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
      
      Rails.logger.info "Processing record_message_sent for lead #{@lead.id}"
      # ... (database update is correct)
      @appointment.update(
        last_message_sent_at: Time.current,
        last_message_sent_by: current_user.name
      )
      
      # This correctly prepares the Content-Type for the direct response
      response.headers["Content-Type"] = "text/vnd.turbo-stream.html"
      
      # This renders the partial that contains the updated HTML
      phone_html = render_to_string(
        partial: "clinic_management/leads/phone_with_message_tracking", 
        locals: { lead: @lead, appointment: @appointment }
      )
      
      # This creates the Turbo Stream payload
      # The target "phone-container-#{@lead.id}" should match the ID in your partial
      turbo_stream_response = <<~HTML
        <turbo-stream action="replace" target="phone-container-#{@lead.id}">
          <template>
            #{phone_html}
          </template>
        </turbo-stream>
      HTML
    
      # This broadcasts the exact same Turbo Stream payload over ActionCable
      # The channel "message_tracking_lead_#{@lead.id}" matches your <turbo-stream-source>
      ActionCable.server.broadcast(
        "message_tracking_lead_#{@lead.id}",
        turbo_stream_response
      )
      
      Rails.logger.info "Sending Turbo Stream response: #{turbo_stream_response.inspect}" # For the direct response
      
      # This renders the Turbo Stream for the fetch request that initiated the action
      render html: turbo_stream_response.html_safe
    end
    
    private

    def set_view_type
      @view_type = mobile_device? ? 'cards' : (params[:view_type] || cookies[:preferred_absent_view] || 'table')
    end

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

        row = [
          {header: "#", content: index + 1},
          {
            header: "Paciente", 
            content: render_to_string(
              partial: "clinic_management/leads/patient_name_with_edit_button", 
              locals: { invitation: ap.invitation }
            ).html_safe, 
            class: "nowrap size_20 patient-name"
          },          
          {header: "Data do atendimento", content: service_content_link(ap), class: "nowrap"},
          {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: ap, message: "" }), id: "appointment-comments-#{ap.id}"},                   
          {header: "Remarcação", content: reschedule_form(new_appointment, ap), class: "text-orange-500"},
          {header: "Comparecimento", content: (ap.attendance == true ? "Sim" : "Não"), class: helpers.attendance_class(ap)},
          {header: "Status", content: ap.status, class: helpers.status_class(ap)},
          {header: "Data do convite", content: invitation&.created_at&.strftime("%d/%m/%Y")},
          {header: "Região", content: invitation&.region&.name},
          {header: "Mensagem", content: generate_message_content(@lead, ap), id: "whatsapp-link-#{@lead.id}"}
        ]

        unless helpers.referral?(current_user)
          row.insert(5, {header: "Receita", content: prescription_link(ap), class: "nowrap"})
          row << {header: "Convidado por", content: invitation&.referral&.name}
          #row << {header: "Mensagem", content: generate_message_content(@lead, ap), id: "whatsapp-link-#{@lead.id}"}
        end

        row
      end
    end

    def service_content_link(ap)
      current_referral = helpers.user_referral if helpers.referral?(current_user)
      is_current_referral_invitation = current_referral && ap.invitation&.referral_id == current_referral.id
      
      service_content = if helpers.referral?(current_user)
        if is_current_referral_invitation
          helpers.link_to(invite_day(ap), clinic_management.show_by_referral_services_path(referral_id: current_referral.id, id: ap.service.id), class: "text-blue-500 hover:text-blue-700")
        else
          invite_day(ap)
        end
      else
        helpers.link_to(invite_day(ap), clinic_management.service_path(ap.service), class: "text-blue-500 hover:text-blue-700")
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
        
        # Get order count information
        order_count = lead&.customer&.orders&.count || 0
        
        # Determine the patient's status with order info on a separate line
        status_content = if last_appointment.attendance == false
          # First line: Patient was absent
          "<div class='text-red-500 font-semibold'>Ausente</div>"
        else
          # First line: Patient attended but more than a year ago
          "<div class='text-orange-500 font-semibold'>Atendeu há mais de 1 ano</div>"
        end
        
        # Add order information as a second line with icon if there are orders
        if order_count > 0
          order_text = "#{order_count} #{order_count == 1 ? 'compra' : 'compras'} na ótica"
          status_content += "<div class='text-blue-600 mt-1'><i class='fas fa-shopping-bag mr-1'></i> #{order_text}</div>"
        end
        
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
              class: "nowrap size_20 patient-name"
            },
            # Status column with separated order information
            {header: "Status", content: status_content.html_safe, class: "!min-w-[300px]"},   
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
            {header: "Último atendimento", content: service_content_link(last_appointment), class: "nowrap"},
            {header: "Remarcação", content: reschedule_form(new_appointment, last_appointment), class: "text-orange-500" },
            {header: "Mensagem", content: generate_message_content(lead, last_appointment), id: "whatsapp-link-#{lead.id}"}
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
              class: "nowrap size_20 patient-name" 
            },
            # Status column with separated order information
            {header: "Status", content: status_content.html_safe, class: "!min-w-[300px]"},
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
            {header: "Último atendimento", content: service_content_link(last_appointment), class: "nowrap"},
            {header: "Remarcação", content: reschedule_form(new_appointment, last_appointment), class: "text-orange-500" },
            {header: "Mensagem", content: generate_message_content(lead, last_appointment), id: "whatsapp-link-#{lead.id}"}
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
      last_appointment.present? ? helpers.link_to("#{invite_day(last_appointment).html_safe}", service_path(last_appointment.service), class: "text-blue-500 hover:text-blue-700", target: "_blank").html_safe : ""
    end
    
    
      def responsible_content(invite)
        if invite.present?
          (invite.lead.name != invite.patient_name) ? invite.lead.name : ""
        else
          ""
        end
      end

      def fetch_leads_by_appointment_condition(base_condition_sql, *condition_values)
        one_year_ago = Date.current - 1.year

        # IDs dos leads que tiveram attendance como true DENTRO do último ano (serão excluídos)
        excluded_lead_ids = ClinicManagement::Appointment.joins(:service)
          .where('clinic_management_appointments.attendance = ? AND clinic_management_services.date >= ?', true, one_year_ago)
          .pluck(:lead_id)

        # Base da query com joins e filtros essenciais
        # Seleciona as colunas necessárias para o distinct e order by
        query = ClinicManagement::Lead
          .select('DISTINCT clinic_management_leads.*, clinic_management_services.date AS service_date_for_ordering')
          .joins(appointments: :service) # Usar appointments para ter acesso a service.date
          .where('clinic_management_leads.last_appointment_id = clinic_management_appointments.id') # Garante que estamos olhando o last_appointment
          .where('clinic_management_appointments.service_id = clinic_management_services.id') # Garante join correto
          .where.not(id: excluded_lead_ids) # Exclui leads com atendimento recente
          .where.not(phone: [nil, '']) # Garante que há telefone

        # Aplica a condição específica (ausentes ou atendidos há mais de 1 ano)
        # A condição base_condition_sql deve referenciar clinic_management_appointments.attendance e clinic_management_services.date
        query = query.where(
          "#{base_condition_sql} OR (clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?)",
          *condition_values, true, one_year_ago
        )
        
        query # Retorna a ActiveRecord::Relation
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