require 'ostruct'

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

    def record_message_sent
      @lead = Lead.find(params[:id])
      @appointment = @lead.appointments.find(params[:appointment_id])
      
      # Criar o registro de interação
      LeadInteraction.create!(
        lead: @lead,
        appointment: @appointment,
        user: current_user,
        interaction_type: params[:interaction_type] || 'whatsapp_click',
        occurred_at: Time.current
      )
      
      # Manter compatibilidade com sistema antigo
      @appointment.update(
        last_message_sent_at: Time.current, 
        last_message_sent_by: current_user.name
      )
      #byebug
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "phone-container-#{@lead.id}",  # Usando o mesmo ID do partial
            partial: "clinic_management/leads/phone_with_message_tracking",
            locals: { lead: @lead, appointment: @appointment }
          )
        end
        #format.json { head :no_content }
      end
    end
    
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
      phone = lead_params[:phone]
      
      if phone.present?
        existing_lead = Lead.find_by(phone: phone)
        
        if existing_lead.present?
          flash[:alert] = "Já existe um lead com este telefone: #{existing_lead.name} (ID: #{existing_lead.id}). Redirecionando para o lead existente."
          redirect_to existing_lead and return
        end
      end
      
      @lead = Lead.new(lead_params)

      if @lead.save
        redirect_to @lead, notice: "Lead was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /leads/1
    def update
      phone = lead_params[:phone]
      
      # Verificar se estamos mudando o telefone para um que já existe
      if phone.present? && @lead.phone != phone
        existing_lead = Lead.find_by(phone: phone)
        
        if existing_lead.present?
          flash[:alert] = "Este telefone já pertence a outro lead: #{existing_lead.name} (ID: #{existing_lead.id})"
          render :edit, status: :unprocessable_entity and return
        end
      end
      
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
      # Removida a diferenciação - usar sempre 1.day.ago para todos
      @all_leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?', false, 1.days.ago)
      
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
      store_absent_leads_state_in_session

      # 1) Carregar a coleção base (com base se é referral ou não)
      @all_leads = base_absent_leads_scope

      # 2) Aplicar filtros sequenciais encapsulados
      @all_leads = filter_leads_with_phone(@all_leads)
      @all_leads = filter_by_patient_type(@all_leads)
      @all_leads = filter_by_date(@all_leads)
      @all_leads = filter_by_contact_status(@all_leads)
      @all_leads = filter_by_referral(@all_leads)  # Novo filtro aqui
      @all_leads = apply_absent_leads_order(@all_leads)

      # 3) Filtro de busca por nome/telefone
      @leads = filter_by_query(@all_leads)

      # 4) Paginação e montagem das linhas
      if params[:tab] == 'download'
        @date_range = (Date.current - 1.year)..Date.current
      else
        @leads = @leads.page(params[:page]).per(50)
        @rows = load_leads_data(@leads)
      end

      # 5) Renderização
      respond_to do |format|
        format.html { render :absent }
        format.html { render :absent_download if params[:view] == 'download' }
      end
    end

    private

    # Armazena o estado da URL de ausentes na sessão, SEMPRE removendo 'page' para sempre começar na página 1
    def store_absent_leads_state_in_session
      return unless request.get?
      uri = URI.parse(request.original_url)
      params_hash = Rack::Utils.parse_nested_query(uri.query || "")
      
      # Sempre remover 'page' para evitar preservar paginação antiga (corrige problema de "inversão" aparente ao voltar)
      params_hash.delete('page')
      
      uri.query = Rack::Utils.build_query(params_hash).presence
      session[:absent_leads_state] = uri.to_s
    end

    # Retorna o escopo base de leads ausentes, sem diferenciação de usuário
    def base_absent_leads_scope
      # Removida a diferenciação - usar sempre 1.day.ago para todos
      absent_threshold_date = 1.day.ago.to_date
      fetch_leads_by_appointment_condition(
        'clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?',
        false,
        absent_threshold_date
      )
    end

    # Filtra leads que possuem telefone válido
    def filter_leads_with_phone(scope)
      scope.where.not(phone: [nil, ''])
    end

    # Filtra por tipo de paciente, se especificado
    def filter_by_patient_type(scope)
      return scope unless params[:patient_type].present? && params[:patient_type] != "all"
      one_year_ago = 1.year.ago.to_date
      case params[:patient_type]
      when "absent"
        scope.joins("INNER JOIN clinic_management_appointments AS latest_apt ON latest_apt.id = (
          SELECT id FROM clinic_management_appointments 
          WHERE lead_id = clinic_management_leads.id 
          ORDER BY created_at DESC 
          LIMIT 1
        )")
        .where('latest_apt.attendance = ?', false)
      when "attended_year_ago"
        scope.where('main_apt.attendance = ? AND main_svc.date < ?', true, one_year_ago)
      else
        scope
      end
    end

    # Filtra por data (ano/mês), se especificado
    def filter_by_date(scope)
      if params[:year].present? && params[:month].present?
        start_date = Date.new(params[:year].to_i, params[:month].to_i, 1)
        end_date = start_date.end_of_month
        scope.where('main_svc.date BETWEEN ? AND ?', start_date, end_date)
      elsif params[:year].present?
        start_date = Date.new(params[:year].to_i, 1, 1)
        end_date = Date.new(params[:year].to_i, 12, 31)
        scope.where('main_svc.date BETWEEN ? AND ?', start_date, end_date)
      else
        scope
      end
    end

    # Filtra por status de contato, se especificado
    def filter_by_contact_status(scope)
      return scope unless params[:contact_status].present? && params[:contact_status] != "all"
      
      case params[:contact_status]
      when "not_contacted"
        scope.where('main_apt.last_message_sent_at IS NULL')
      when "contacted"
        scope.where('main_apt.last_message_sent_at IS NOT NULL')
      when "contacted_by_me"
        scope.where('main_apt.last_message_sent_at IS NOT NULL AND main_apt.last_message_sent_by = ?', current_user.name)
      else
        scope
      end
    end

    # Novo filtro para referral
    def filter_by_referral(scope)
      return scope unless helpers.referral?(current_user)
      
      current_referral = helpers.user_referral
      cutoff_date = 120.days.ago.to_date
      
      # Obter IDs dos leads que têm appointments nos últimos 120 dias que NÃO são do referral atual
      excluded_lead_ids = ClinicManagement::Lead
        .joins(appointments: [:service, :invitation])
        .where('clinic_management_services.date >= ?', cutoff_date)
        .where.not('clinic_management_invitations.referral_id = ?', current_referral.id)
        .pluck(:id)
      
      # Excluir esses leads do escopo
      scope.where.not(id: excluded_lead_ids)
    end

    # Aplica ordenação conforme o parâmetro de sort
    def apply_absent_leads_order(scope)
      sort_order = params[:sort_order] || 'appointment_newest_first'
      case sort_order
      when "appointment_newest_first"
        scope.order('main_svc.date DESC')
      when "appointment_oldest_first"
        scope.order('main_svc.date ASC')
      when "contact_newest_first"
        # Contato mais recente: usar dados unificados (lead_interactions + appointment)
        scope.reorder('unified_last_contact_at DESC NULLS LAST')
      when "contact_oldest_first"
        # Contato há mais tempo: usar dados unificados (lead_interactions + appointment)
        scope.reorder('unified_last_contact_at ASC NULLS LAST')
      else
        scope.order('main_svc.date DESC')
      end
    end

    # Filtra por busca de nome/telefone, se houver query
    def filter_by_query(scope)
      query = params[:q]&.strip
      if query.present?
        scope.distinct.where(
          "clinic_management_leads.name ILIKE ? OR clinic_management_leads.phone ILIKE ?",
          "%#{query}%",
          "%#{query}%"
        )
      else
        scope.distinct
      end
    end

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
        
        # ✅ CORREÇÃO: Usar dados unificados da query (lead_interactions + appointment)
        # Criar um objeto appointment que usa os dados já carregados da query
        last_appointment = OpenStruct.new(
          id: lead.current_appointment_id,
          last_message_sent_at: lead.unified_last_contact_at,
          last_message_sent_by: lead.unified_last_contact_by,
          attendance: false  # Sabemos que é ausente pela query
        )
        
        # Para funcionalidades que precisam do appointment completo, buscar quando necessário
        full_appointment = nil
        
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
        
        new_appointment = ClinicManagement::Appointment.new

        # Função helper para buscar appointment completo quando necessário
        get_full_appointment = lambda do
          full_appointment ||= ClinicManagement::Appointment.find(lead.current_appointment_id)
        end

        # Removida a diferenciação - usar sempre a estrutura completa para todos
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
          {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: get_full_appointment.call, message: "" }), id: "appointment-comments-#{last_appointment.id}"},
          {header: "Último indicador", content: last_referral(last_invitation)},
          {header: "Qtd. de convites", content: lead.invitations.count},
          {header: "Qtd. de atendimentos", content: lead.appointments.count},
          {header: "Último atendimento", content: service_content_link(get_full_appointment.call), class: "nowrap"},
          {header: "Remarcação", content: reschedule_form(new_appointment, get_full_appointment.call), class: "text-orange-500" },
          {header: "Mensagem", content: generate_message_content(lead, get_full_appointment.call), id: "whatsapp-link-#{lead.id}"}
        ]
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

      def fetch_leads_by_appointment_condition(query_condition, value, date = nil)
        one_year_ago = Date.current - 1.year

        # 1. Leads que compareceram no último ano (excluir)
        excluded_lead_ids = ClinicManagement::Appointment.joins(:service)
          .where('clinic_management_appointments.attendance = ? AND clinic_management_services.date >= ?', true, one_year_ago)
          .pluck(:lead_id)

        # 2. Query mais simples e direta com unificação de dados
        base_query = ClinicManagement::Lead
          .joins("INNER JOIN clinic_management_appointments AS main_apt ON clinic_management_leads.last_appointment_id = main_apt.id")
          .joins("INNER JOIN clinic_management_services AS main_svc ON main_apt.service_id = main_svc.id")
          .joins("LEFT JOIN clinic_management_lead_interactions AS latest_interaction ON clinic_management_leads.id = latest_interaction.lead_id AND latest_interaction.occurred_at = (SELECT MAX(occurred_at) FROM clinic_management_lead_interactions WHERE lead_id = clinic_management_leads.id)")
          .joins("LEFT JOIN users AS interaction_user ON latest_interaction.user_id = interaction_user.id")
          .select(
            'clinic_management_leads.*',
            'main_svc.date as service_date',
            'main_apt.last_message_sent_at',
            'main_apt.last_message_sent_by',
            'main_apt.id as current_appointment_id',
            'latest_interaction.occurred_at as latest_interaction_at',
            'interaction_user.name as latest_interaction_by',
            # Usar a data mais recente entre as duas fontes para ordenação
            'COALESCE(latest_interaction.occurred_at, main_apt.last_message_sent_at) as unified_last_contact_at',
            'COALESCE(interaction_user.name, main_apt.last_message_sent_by) as unified_last_contact_by'
          )
          .where.not(id: excluded_lead_ids)

        # 3. Aplicar condições de forma mais simples
        if date
          # Para a condition com data
          base_query = base_query.where(
            "(main_apt.attendance = ? AND main_svc.date < ?) OR (main_apt.attendance = ? AND main_svc.date < ?)",
            false, date,
            true, one_year_ago
          )
        else
          # Para condition simples
          base_query = base_query.where('main_apt.attendance = ?', false)
        end
        
        base_query
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
          # ✅ CORREÇÃO: Usar appointment completo quando necessário para CSV
          last_appointment = ClinicManagement::Appointment.find(lead.current_appointment_id)

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
        # Removida a diferenciação - usar sempre a estrutura padrão para todos
        leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ?', false)
        
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