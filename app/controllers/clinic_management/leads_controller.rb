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
      
      # Verificar se já existe uma interação recente (última hora) para evitar duplicações
      last_interaction = @lead.lead_interactions
        .where(appointment: @appointment, interaction_type: params[:interaction_type] || 'whatsapp_click')
        .where('occurred_at > ?', 1.hour.ago)
        .order(occurred_at: :desc)
        .first
      
      @cooldown_active = last_interaction.present?
      
      # Se não houver interação na última hora, criar nova
      if last_interaction.blank?
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
      end
      
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
    
    # POST /leads/:id/make_call
    # Inicia uma chamada telefônica através da API Direct Call
    def make_call
      @lead = Lead.find(params[:id])
      @appointment = @lead.appointments.find(params[:appointment_id])
      @context = params[:context] || 'other'  # 'absent' ou 'other'
      
      # Verificar se Direct Call está configurado para a conta
      unless current_account.directcall_configured?
        return render json: { 
          success: false, 
          error: 'Direct Call não está configurado para esta conta' 
        }, status: :unprocessable_entity
      end
      
      # Verificar se o usuário está habilitado para usar Direct Call
      unless current_user.directcall_enabled
        return render json: { 
          success: false, 
          error: 'Você não está habilitado para fazer chamadas. Contate o administrador.' 
        }, status: :unprocessable_entity
      end
      
      # Nota: directcall_origem_user é opcional
      # Se o usuário não tiver número próprio, o service usará o número padrão da conta
      # (validado em directcall_configured?)
      
      # Iniciar chamada via Direct Call com contexto e número do usuário
      service = DirectcallService.new(current_account)
      
      Rails.logger.info "📞 Direct Call: Iniciando ligação manual para #{@lead.name}"
      
      result = service.make_call(
        @lead.phone,
        lead_id: @lead.id,
        appointment_id: @appointment.id,
        context: @context,
        user_origem: current_user.directcall_origem_user
      )
      
      if result[:success]
        # NÃO registrar interação aqui - será registrada pelo webhook quando confirmar que foi atendida
        Rails.logger.info "📞 Direct Call: Chamada iniciada - Call ID: #{result[:call_id]} - aguardando confirmação via webhook"
        
        # Manter compatibilidade com sistema antigo (marca que tentou contato)
        @appointment.update(
          last_message_sent_at: Time.current,
          last_message_sent_by: current_user.name
        )
        
        render json: {
          success: true,
          message: 'Chamada iniciada com sucesso',
          call_id: result[:call_id]
        }
      else
        render json: {
          success: false,
          error: result[:error]
        }, status: :unprocessable_entity
      end
      
    rescue StandardError => e
      Rails.logger.error "❌ Erro ao iniciar chamada: #{e.message}"
      render json: {
        success: false,
        error: e.message
      }, status: :internal_server_error
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
        # Sanitizar o telefone para busca (remover caracteres da máscara)
        clean_phone = phone.gsub(/\D/, '')
        existing_lead = Lead.find_by(phone: clean_phone)
        
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
        # Sanitizar o telefone para busca (remover caracteres da máscara)
        clean_phone = phone.gsub(/\D/, '')
        existing_lead = Lead.find_by(phone: clean_phone)
        
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

      @rows = load_leads_data(@leads, 'absent')

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

    def hide_from_absent
      @lead = ClinicManagement::Lead.find(params[:id])
      @lead.update!(hidden_from_absent: true)
      
      respond_to do |format|
        format.turbo_stream do
          # Se vier da página show, redirecionar para atualizar a interface
          if request.referer&.include?("/leads/#{@lead.id}")
            redirect_to lead_path(@lead), notice: "Lead ocultado da listagem com sucesso"
          else
            # Se vier da listagem, apenas remover o card
            render turbo_stream: turbo_stream.remove("lead-card-#{@lead.id}")
          end
        end
        format.html do
          redirect_to lead_path(@lead), notice: "Lead ocultado da listagem com sucesso"
        end
        format.json { render json: { success: true, message: "Lead ocultado da listagem com sucesso" } }
      end
    end

    def mark_no_whatsapp
      @lead = ClinicManagement::Lead.find(params[:id])
      @lead.update!(no_whatsapp: true)
      
      respond_to do |format|
        format.turbo_stream do
          # Se vier da página show, redirecionar para atualizar a interface
          if request.referer&.include?("/leads/#{@lead.id}")
            redirect_to lead_path(@lead), notice: "Lead marcado como 'sem whatsapp'"
          else
            # Se vier da listagem, apenas remover o card
            render turbo_stream: turbo_stream.remove("lead-card-#{@lead.id}")
          end
        end
        format.html do
          redirect_to lead_path(@lead), notice: "Lead marcado como 'sem whatsapp'"
        end
        format.json { render json: { success: true, message: "Lead marcado como 'sem whatsapp'" } }
      end
    end

    def mark_no_interest
      @lead = ClinicManagement::Lead.find(params[:id])
      @lead.update!(no_interest: true)
      
      respond_to do |format|
        format.turbo_stream do
          # Se vier da página show, redirecionar para atualizar a interface
          if request.referer&.include?("/leads/#{@lead.id}")
            redirect_to lead_path(@lead), notice: "Lead marcado como 'sem interesse'"
          else
            # Se vier da listagem, apenas remover o card
            render turbo_stream: turbo_stream.remove("lead-card-#{@lead.id}")
          end
        end
        format.html do
          redirect_to lead_path(@lead), notice: "Lead marcado como 'sem interesse'"
        end
        format.json { render json: { success: true, message: "Lead marcado como 'sem interesse'" } }
      end
    end

    def toggle_whatsapp_status
      @lead = ClinicManagement::Lead.find(params[:id])
      Rails.logger.info "Before toggle: no_whatsapp = #{@lead.no_whatsapp}"
      @lead.toggle_whatsapp_status!
      Rails.logger.info "After toggle: no_whatsapp = #{@lead.no_whatsapp}"
      
      respond_to do |format|
        format.json { render json: { success: true, no_whatsapp: @lead.no_whatsapp } }
      end
    rescue => e
      Rails.logger.error "Error toggling WhatsApp status: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message } }
      end
    end

    def restore_lead
      @lead = ClinicManagement::Lead.find(params[:id])
      @lead.update!(
        hidden_from_absent: false,
        no_whatsapp: false,
        no_interest: false
      )
      
      respond_to do |format|
        format.turbo_stream do
          # Se vier da página show, redirecionar de volta para show
          if request.referer&.include?("/leads/#{@lead.id}")
            redirect_to lead_path(@lead), notice: "Lead restaurado na listagem com sucesso"
          else
            # Se vier da listagem, recarregar a página de ausentes
            redirect_to absent_leads_path
          end
        end
        format.html do
          redirect_to lead_path(@lead), notice: "Lead restaurado na listagem com sucesso"
        end
        format.json { render json: { success: true, message: "Lead restaurado na listagem com sucesso" } }
      end
    end

    def check_phone
      phone = params[:phone]&.gsub(/\D/, '')
      lead_id = params[:lead_id].to_i
      
      existing_lead = Lead.find_by(phone: phone)
      
      if existing_lead.present? && existing_lead.id != lead_id
        render json: {
          exists: true,
          lead_name: existing_lead.name,
          lead_id: existing_lead.id
        }
      else
        render json: { exists: false }
      end
    end

    def absent
      # Store the URL, potentially modified, in the session on GET requests
      store_absent_leads_state_in_session
      
      # 1) Carregar a coleção base (com base se é referral ou não)
      @all_leads = base_absent_leads_scope

      # 2) Aplicar filtros sequenciais encapsulados
      @all_leads = filter_leads_with_phone(@all_leads)
      @all_leads = filter_by_whatsapp_status(@all_leads)  # Novo filtro de WhatsApp
      @all_leads = filter_by_hidden_status(@all_leads)  # Filtro de ocultação/interesse
      @all_leads = filter_by_patient_type(@all_leads)
      @all_leads = filter_by_date(@all_leads)
      @all_leads = filter_by_contact_status(@all_leads)
      @all_leads = filter_by_referral(@all_leads)  # Novo filtro aqui
      @all_leads = filter_by_page_views(@all_leads)  # 🆕 Filtrar leads visualizados por outros
      @all_leads = apply_absent_leads_order(@all_leads)

      # 3) Filtro de busca por nome/telefone
      @leads = filter_by_query(@all_leads)

      # 4) Paginação e montagem das linhas
      if params[:tab] == 'download'
        @date_range = (Date.current - 1.year)..Date.current
      else
        @leads = @leads.page(params[:page]).per(50)
        
        # 🆕 Registrar visualização dos leads desta página
        register_page_views(@leads)
        
        @rows = load_leads_data(@leads, 'absent')
      end

      # 5) Limpeza de visualizações expiradas (executar ocasionalmente)
      cleanup_expired_views if should_cleanup?

      # 6) Renderização
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

    # Filtra por status de WhatsApp
    def filter_by_whatsapp_status(scope)
      case params[:whatsapp_status]
      when "has_whatsapp"
        scope.where(no_whatsapp: [false, nil])  # nil defaults to has whatsapp
      when "no_whatsapp"
        scope.where(no_whatsapp: true)
      else
        # Default: mostrar todos independente do status WhatsApp
        scope
      end
    end

    # Filtra por status de interesse/visibilidade
    def filter_by_hidden_status(scope)
      case params[:hidden_status]
      when "hidden"
        scope.where(hidden_from_absent: true)
      when "no_interest"
        scope.where(no_interest: true)
      when "visible"
        scope.where(
          hidden_from_absent: [false, nil],
          no_interest: [false, nil]
        )
      else
        # Default: sempre excluir leads com status especial da listagem principal
        scope.where(
          hidden_from_absent: [false, nil],
          no_interest: [false, nil]
        )
      end
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
      when "attended_year_ago_customer"
        # Pacientes que compareceram há mais de um ano E são clientes (têm orders)
        scope.where('main_apt.attendance = ? AND main_svc.date < ?', true, one_year_ago)
             .where('EXISTS (
               SELECT 1 FROM leads_conversions lc 
               INNER JOIN customers c ON lc.customer_id = c.id
               INNER JOIN orders o ON c.id = o.customer_id 
               WHERE lc.clinic_management_lead_id = clinic_management_leads.id
             )')
      when "attended_year_ago_non_customer"
        # Pacientes que compareceram há mais de um ano E NÃO são clientes (não têm orders)
        scope.where('main_apt.attendance = ? AND main_svc.date < ?', true, one_year_ago)
             .where('NOT EXISTS (
               SELECT 1 FROM leads_conversions lc 
               INNER JOIN customers c ON lc.customer_id = c.id
               INNER JOIN orders o ON c.id = o.customer_id 
               WHERE lc.clinic_management_lead_id = clinic_management_leads.id
             )')
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
      
      # Se o referral não tem permissão de acessar todos os leads (can_access_leads = false),
      # mostrar apenas os leads cujos appointments foram feitos através DELE (via invitation)
      unless current_referral&.can_access_leads
        # Buscar IDs dos leads que têm appointments com invitations do referral atual
        allowed_lead_ids = ClinicManagement::Lead
          .joins(appointments: :invitation)
          .where('clinic_management_invitations.referral_id = ?', current_referral.id)
          .distinct
          .pluck('clinic_management_leads.id')
        
        # Retornar apenas esses leads
        return scope.where('clinic_management_leads.id IN (?)', allowed_lead_ids.presence || [0])
      end
      
      # Se tem permissão (can_access_leads = true), aplicar filtro antigo de referral
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
    

    def generate_message_content(lead, appointment, context = nil)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: lead, appointment: appointment, context: context }
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
          {header: "Status", content: ap.status, class: "size_20 " + helpers.status_class(ap)},
          {header: "Data do convite", content: invitation&.created_at&.strftime("%d/%m/%Y")},
          {header: "Região", content: invitation&.region&.name},
          {header: "Mensagem", content: generate_message_content(@lead, ap, 'show'), id: "whatsapp-link-#{@lead.id}"}
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

    def load_leads_data(leads, context = nil)
      leads.map.with_index do |lead, index|
        last_invitation = lead.invitations.last
        
        # ✅ CORREÇÃO: SEMPRE buscar o appointment real para determinar attendance correto
        # A página "absent" pode conter:
        # 1. Leads que faltaram no último atendimento (attendance = false)
        # 2. Leads que compareceram há mais de 1 ano (attendance = true, mas antiga)
        # Portanto, NÃO podemos assumir attendance baseado apenas no contexto!
        real_appointment = ClinicManagement::Appointment.find_by(id: lead.current_appointment_id)
        attendance_value = real_appointment&.attendance || false
        
        # Criar um objeto appointment que usa os dados já carregados da query
        last_appointment = OpenStruct.new(
          id: lead.current_appointment_id,
          last_message_sent_at: lead.unified_last_contact_at,
          last_message_sent_by: lead.unified_last_contact_by,
          attendance: attendance_value
        )
        
        # Para funcionalidades que precisam do appointment completo, buscar quando necessário
        full_appointment = nil
        
        # Get order count information
        order_count = lead&.customer&.orders&.count || 0
        
        # Determine the patient's status with order info on a separate line
        status_content = if last_appointment.attendance == false
          # First line: Patient was absent
          "<div class='text-red-500 font-semibold size_20'>Ausente</div>"
        else
          # First line: Patient attended but more than a year ago
          "<div class='text-orange-500 font-semibold size_20'>Compareceu há mais de 1 ano</div>"
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
          {
            header: "Ordem", 
            content: index + 1, 
            row_id: "lead-row-#{lead.id}",  # ID único para highlight
            row_class: ""  # Classe será manipulada via JS para highlight
          },
          {
            header: "Paciente", 
            content: render_to_string(
              partial: "clinic_management/leads/patient_name_with_edit_button", 
              locals: { invitation: last_invitation }
            ).html_safe, 
            class: "nowrap size_20 patient-name" 
          },
          # Status column with separated order information
          {header: "Status", content: status_content.html_safe, class: "!min-w-[300px] size_20 " + helpers.status_class(last_appointment)},
          {header: "Responsável", content: responsible_content(last_invitation), class: "nowrap"},
          {
            header: "Telefone", 
            content: render_to_string(
              partial: "clinic_management/leads/phone_with_message_tracking", 
              locals: { lead: lead, appointment: last_appointment, persist_hint: (context == 'absent') }
            ).html_safe,
            class: "text-blue-500 hover:text-blue-700 nowrap"
          },
          {header: "Mensagem", content: generate_message_content(lead, get_full_appointment.call, context), id: "whatsapp-link-#{lead.id}"},
          {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: get_full_appointment.call, message: "" }), id: "appointment-comments-#{last_appointment.id}"},
          {header: "Último atendimento", content: service_content_link(get_full_appointment.call), class: "nowrap"},
          {header: "Remarcação", content: reschedule_form(new_appointment, get_full_appointment.call), class: "text-orange-500" },
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
        params.require(:clinic_management_appointment).permit(:comments, :registered_by_user)
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

      # 🆕 Filtrar leads que estão sendo visualizados por outros usuários
      def filter_by_page_views(scope)
        # Obter IDs dos leads que estão bloqueados para este usuário
        blocked_ids = ClinicManagement::LeadPageView.blocked_lead_ids_for_user(
          current_user.id,
          context: 'absent'
        )
        
        # Se houver leads bloqueados, excluí-los do resultado
        if blocked_ids.any?
          Rails.logger.info "🔒 Filtrando #{blocked_ids.count} leads reservados por outros usuários"
          scope.where.not(id: blocked_ids)
        else
          scope
        end
      end

      # 🆕 Registrar visualização dos leads da página atual
      def register_page_views(leads)
        return if leads.blank?
        
        lead_ids = leads.map(&:id)
        
        # Registrar cada lead como visualizado pelo usuário atual
        lead_ids.each do |lead_id|
          ClinicManagement::LeadPageView.register_view(
            lead_id,
            current_user.id,
            context: 'absent',
            duration_hours: 3
          )
        end
        
        Rails.logger.info "✅ Registradas #{lead_ids.count} visualizações para usuário #{current_user.id}"
      rescue StandardError => e
        # Não quebrar a aplicação se houver erro no registro
        Rails.logger.error "❌ Erro ao registrar visualizações: #{e.message}"
      end

      # 🆕 Decidir se deve limpar visualizações expiradas
      def should_cleanup?
        # Limpar apenas ocasionalmente (10% das requisições)
        # ou se for o primeiro acesso do dia
        rand(100) < 10 || session[:last_cleanup_date] != Date.current.to_s
      end

      # 🆕 Limpar visualizações expiradas
      def cleanup_expired_views
        deleted_count = ClinicManagement::LeadPageView.cleanup_expired
        session[:last_cleanup_date] = Date.current.to_s
        Rails.logger.info "🧹 Limpeza: #{deleted_count} visualizações expiradas removidas"
      rescue StandardError => e
        Rails.logger.error "❌ Erro na limpeza: #{e.message}"
      end
  end
end