require 'ostruct'

module ClinicManagement
  class LeadsController < ApplicationController
    before_action :set_lead, only: %i[ show edit update destroy ]
    before_action :set_menu, only: %i[ index absent attended cancelled ]
    before_action :set_referral, only: %i[ index absent attended cancelled ]
    skip_before_action :redirect_referral_users
    before_action :set_view_type, only: [:absent]

    include GeneralHelper
    include MessagesHelper
    
    # Make can_use_evolution_api? available in views
    helper_method :can_use_evolution_api?
    helper_method :bulk_interval_margin_percent, :bulk_interval_default_seconds, :bulk_interval_min_seconds, :bulk_interval_max_seconds

    # ==========================================================================
    # BULK MESSAGE INTERVAL CONFIGURATION (envio em massa)
    # ==========================================================================
    # User-defined interval (seconds) between each message. Backend applies a
    # random margin (BULK_INTERVAL_MARGIN_PERCENT) so the actual interval is
    # interval_seconds + rand(0..margin) to avoid exact timing and blocking.
    # ==========================================================================
    BULK_INTERVAL_MIN_SECONDS = 10   # Minimum allowed (avoid too fast)
    BULK_INTERVAL_MAX_SECONDS = 3600 # Maximum 1 hour between messages
    BULK_INTERVAL_MARGIN_PERCENT = 30 # Random extra: 0 to 30% of interval (backend-only)
    BULK_INTERVAL_DEFAULT_SECONDS = 60 # Default when user does not set (fallback in view)

    def bulk_interval_margin_percent
      BULK_INTERVAL_MARGIN_PERCENT
    end

    def bulk_interval_default_seconds
      BULK_INTERVAL_DEFAULT_SECONDS
    end

    def bulk_interval_min_seconds
      BULK_INTERVAL_MIN_SECONDS
    end

    def bulk_interval_max_seconds
      BULK_INTERVAL_MAX_SECONDS
    end

    # GET /leads
    # def index
      # @leads = Lead.includes(:invitations, :appointments).page(params[:page]).per(50)
      # @rows = load_leads_data(@leads)
    # end

    def record_message_sent
      @lead = Lead.find(params[:id])
      @appointment = @lead.appointments.find(params[:appointment_id])
      interaction_type = params[:interaction_type] || 'whatsapp_click'
      
      # =======================================================
      # VERIFICAÇÃO DE WHATSAPP ANTES DE REGISTRAR INTERAÇÃO
      # Se for whatsapp_click, verifica se o número tem WhatsApp
      # =======================================================
      @no_whatsapp_detected = false
      
      if interaction_type == 'whatsapp_click' && can_use_evolution_api?
        Rails.logger.info "[RECORD MSG] Verificando WhatsApp para Lead ##{@lead.id}: #{@lead.phone}"

        # ESSENTIAL: Referrals must use their own instances — never clinic's.
        # If no instance available, fail early instead of falling back to clinic.
        instance_name = get_evolution_instance_name
        if instance_name.blank?
          flash[:alert] = "Nenhuma instância WhatsApp conectada. Configure sua conexão em WhatsApp."
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update("flash", partial: "shared/flash_messages"), status: :unprocessable_entity
            end
          end
          return
        end

        # Verificar se o número tem WhatsApp
        whatsapp_check = helpers.check_whatsapp_number(@lead.phone, instance_name)
        
        # IMPORTANTE: Só marcar como sem WhatsApp se a verificação foi bem-sucedida
        # e o número realmente não existe. Se houve erro na API, não alterar o status.
        if whatsapp_check[:exists] == false && whatsapp_check[:error].blank?
          Rails.logger.warn "[RECORD MSG] ⚠️ Número confirmado sem WhatsApp: #{@lead.phone}"
          
          # Marcar lead como sem WhatsApp
          @lead.update(no_whatsapp: true)
          @no_whatsapp_detected = true
          
          # NÃO registrar interação - número não tem WhatsApp
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                "phone-container-#{@lead.id}",
                partial: "clinic_management/leads/phone_with_message_tracking",
                locals: { lead: @lead.reload, appointment: @appointment, no_whatsapp_alert: true }
              )
            end
          end
          return
        elsif whatsapp_check[:error].present?
          Rails.logger.warn "[RECORD MSG] ⚠️ Erro na verificação de WhatsApp (ignorando): #{whatsapp_check[:error]}"
          # Continuar normalmente - não alterar status do lead quando há erro na API
        else
          Rails.logger.info "[RECORD MSG] ✅ Número tem WhatsApp: #{@lead.phone}"
        end
      end
      
      # Verificar se já existe uma interação recente (última hora) para evitar duplicações
      last_interaction = @lead.lead_interactions
        .where(appointment: @appointment, interaction_type: interaction_type)
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
          interaction_type: interaction_type,
          occurred_at: Time.current
        )
        
        # Manter compatibilidade com sistema antigo
        @appointment.update(
          last_message_sent_at: Time.current, 
          last_message_sent_by: current_user.name
        )
        
        # Register the custom message name in messages_sent if message_id is provided
        # This is called when user clicks "Enviar manualmente" or "Copiar mensagem"
        if params[:message_id].present?
          message = LeadMessage.find_by(id: params[:message_id])
          if message.present? && !@appointment.messages_sent.include?(message.name)
            @appointment.messages_sent << message.name
            @appointment.save
            Rails.logger.info "[RECORD MSG] Added '#{message.name}' to messages_sent for appointment ##{@appointment.id}"
          end
        end
      end
      
      #byebug
      respond_to do |format|
        format.turbo_stream do
          streams = [
            turbo_stream.replace(
              "phone-container-#{@lead.id}",  # Usando o mesmo ID do partial
              partial: "clinic_management/leads/phone_with_message_tracking",
              locals: { lead: @lead, appointment: @appointment }
            )
          ]
          
          # Also update the messages-sent column if message was registered
          if params[:message_id].present?
            streams << turbo_stream.update(
              "messages-sent-#{@appointment.id}",
              @appointment.reload.messages_sent.join(', ')
            )
          end
          
          render turbo_stream: streams
        end
        #format.json { head :no_content }
      end
    end
    
    # POST /leads/:id/verify_whatsapp
    # Verifica se o número do lead possui WhatsApp antes de abrir o link
    # Usado para feedback visual ao usuário
    def verify_whatsapp
      @lead = Lead.find(params[:id])
      
      Rails.logger.info "[VERIFY WHATSAPP] Verificando Lead ##{@lead.id}: #{@lead.phone}"
      
      # SEMPRE verificar, mesmo que já esteja marcado como sem WhatsApp
      # O número pode ter passado a ter WhatsApp depois
      
      # Verificar se Evolution API está disponível
      unless can_use_evolution_api?
        Rails.logger.warn "[VERIFY WHATSAPP] ⚠️ Evolution API não disponível, assumindo que tem WhatsApp"
        return render json: {
          has_whatsapp: true,
          message: "Verificação não disponível, assumindo que tem WhatsApp"
        }
      end
      
      # Obter nome da instância do usuário atual
      # ESSENTIAL: Referrals must use their own instances — never clinic's.
      instance_name = get_evolution_instance_name
      if instance_name.blank?
        return render json: {
          has_whatsapp: false,
          api_error: true,
          message: "Nenhuma instância WhatsApp conectada. Configure sua conexão em WhatsApp.",
          error: "no_instance"
        }
      end

      # Verificar se o número tem WhatsApp via Evolution API
      whatsapp_check = helpers.check_whatsapp_number(@lead.phone, instance_name)
      
      Rails.logger.info "[VERIFY WHATSAPP] Resultado: #{whatsapp_check.inspect}"
      
      if whatsapp_check[:exists] == true
        Rails.logger.info "[VERIFY WHATSAPP] ✅ Número TEM WhatsApp: #{@lead.phone}"
        
        # Se estava marcado como sem WhatsApp, atualizar
        if @lead.no_whatsapp?
          @lead.update(no_whatsapp: false)
          Rails.logger.info "[VERIFY WHATSAPP] 🔄 Lead atualizado: no_whatsapp = false"
        end
        
        render json: {
          has_whatsapp: true,
          jid: whatsapp_check[:jid],
          message: "Número possui WhatsApp"
        }
        
      elsif whatsapp_check[:exists] == false && whatsapp_check[:error].blank?
        Rails.logger.info "[VERIFY WHATSAPP] ❌ Número NÃO tem WhatsApp: #{@lead.phone}"
        
        # Marcar lead como sem WhatsApp
        @lead.update(no_whatsapp: true)
        
        render json: {
          has_whatsapp: false,
          message: "Este número não possui WhatsApp"
        }
        
      else
        # Erro na verificação - NÃO abrir o link, mostrar erro ao usuário
        Rails.logger.warn "[VERIFY WHATSAPP] ⚠️ Erro na verificação: #{whatsapp_check[:error]}"
        
        render json: {
          has_whatsapp: false,
          api_error: true,
          message: "Erro ao verificar WhatsApp: #{whatsapp_check[:error]}",
          error: whatsapp_check[:error]
        }
      end
      
    rescue => e
      Rails.logger.error "[VERIFY WHATSAPP] ❌ Exceção: #{e.class} - #{e.message}"
      
      # Em caso de exceção, NÃO abrir o link
      render json: {
        has_whatsapp: false,
        api_error: true,
        message: "Erro na verificação: #{e.message}",
        error: e.message
      }
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
      
      # ESSENTIAL: available_services filtered by navbar location when multi-regions enabled.
      # Ensures reschedule form only shows services for the selected locality.
      scope = ClinicManagement::Service.where(canceled: [nil, false]).where("date >= ?", Date.current).order(date: :asc)
      loc_filter = current_account&.multi_service_locations_enabled? ? current_service_location_id.to_s : nil
      @available_services = loc_filter.nil? ? scope : scope.merge(ClinicManagement::Service.for_location(loc_filter))
      @available_services = @available_services.includes(:service_location)

      # Label for user reminder: which locality the reschedule form is operating under
      @current_location_label = if current_account&.multi_service_locations_enabled? && ClinicManagement::ServiceLocation.any?
        current_service_location_id.blank? ? "Interno" : (current_service_location_id.to_s == "all" ? "Todos externos" : (ClinicManagement::ServiceLocation.find_by(id: current_service_location_id)&.name || "Interno"))
      else
        nil
      end
      
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
                                      locals: { leads: @leads, available_services: @available_services, current_location_label: @current_location_label })
        end
      end
    end

    def search_absents
      query = params[:q]&.strip
      loc_filter = current_account&.multi_service_locations_enabled? ? current_service_location_id.to_s : nil
      @all_leads = fetch_leads_by_appointment_condition(
        'clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?',
        false,
        1.days.ago,
        service_location_filter: loc_filter
      )
      
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

    def mark_wrong_phone
      @lead = ClinicManagement::Lead.find(params[:id])
      @lead.update!(wrong_phone: true)
      
      respond_to do |format|
        format.turbo_stream do
          # Se vier da página show, redirecionar para atualizar a interface
          if request.referer&.include?("/leads/#{@lead.id}")
            redirect_to lead_path(@lead), notice: "Lead marcado como 'telefone errado'"
          else
            # Se vier da listagem, apenas remover o card
            render turbo_stream: turbo_stream.remove("lead-card-#{@lead.id}")
          end
        end
        format.html do
          redirect_to lead_path(@lead), notice: "Lead marcado como 'telefone errado'"
        end
        format.json { render json: { success: true, message: "Lead marcado como 'telefone errado'" } }
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
        no_interest: false,
        wrong_phone: false
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

    # ============================================================================
    # Check if a phone number already belongs to another lead
    # Used for real-time validation in forms
    # 
    # @param phone [String] - phone number to check
    # @param lead_id [Integer] - current lead ID to exclude from search
    # @returns [JSON] - { exists: true/false, lead_name, lead_id }
    # ============================================================================
    def check_phone
      phone = params[:phone]&.gsub(/\D/, '')
      lead_id = params[:lead_id].to_i
      
      # ESSENTIAL: Don't search for empty phone - would match leads without phone
      if phone.blank?
        render json: { exists: false }
        return
      end
      
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

      # 2) Aplicar filtros sequenciais encapsulados (service_location já no base_absent_leads_scope)
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
    
    # POST /leads/send_bulk_messages
    # Envia mensagens em massa para múltiplos leads via Evolution API
    def send_bulk_messages
      begin
        # Validar permissões
        unless can_use_evolution_api?
          render json: {
            success: false,
            error: 'Você não tem permissão para usar a API Evolution'
          }, status: :forbidden
          return
        end
        
        # Obter parâmetros
        lead_ids = params[:lead_ids] || []
        message_id = params[:message_id]
        interval_seconds = params[:interval_seconds].presence&.to_i

        # Optional: custom interval between messages (seconds). Margin applied in backend.
        bulk_base_delay = nil
        bulk_random_delay = nil
        if interval_seconds.present? && interval_seconds >= BULK_INTERVAL_MIN_SECONDS && interval_seconds <= BULK_INTERVAL_MAX_SECONDS
          bulk_base_delay = interval_seconds
          bulk_random_delay = (interval_seconds * BULK_INTERVAL_MARGIN_PERCENT / 100.0).round
          bulk_random_delay = 1 if bulk_random_delay < 1
          Rails.logger.info "📤 [BULK] Intervalo personalizado: #{bulk_base_delay}s + margem 0-#{bulk_random_delay}s (#{BULK_INTERVAL_MARGIN_PERCENT}%)"
        end

        # Validações básicas
        if lead_ids.blank?
          render json: {
            success: false,
            error: 'Nenhum lead selecionado'
          }, status: :unprocessable_entity
          return
        end
        
        if message_id.blank?
          render json: {
            success: false,
            error: 'Nenhuma mensagem selecionada'
          }, status: :unprocessable_entity
          return
        end
        
        # Buscar leads e message
        leads = Lead.where(id: lead_ids)
        message = ClinicManagement::LeadMessage.find_by(id: message_id)
        
        if message.nil?
          render json: {
            success: false,
            error: 'Mensagem não encontrada'
          }, status: :not_found
          return
        end
        
        # Contadores e dados de resultado
        success_count = 0
        error_count = 0
        skipped_no_whatsapp = 0  # Contador de leads sem WhatsApp (pulados)
        errors_details = []
        queued_messages = []  # Array para armazenar dados de cada mensagem enfileirada
        skipped_leads = []    # Array para leads pulados (sem WhatsApp)

        # ============================================================
        # INSTANCE SELECTION: Round-robin across connected instances
        # ============================================================
        # For referrals with multiple WhatsApp instances, messages alternate
        # between instances (A → B → A → B ...). Each instance has its own
        # independent queue, so total throughput scales with instance count.
        #
        # For non-referrals or single-instance referrals, all messages go
        # to the single available instance.
        #
        # The delay_multiplier is NOT applied because each instance's queue
        # already handles its own timing independently.
        # ============================================================
        available_instances = get_bulk_instance_names
        instance_index = 0  # Round-robin counter

        if available_instances.blank?
          render json: {
            success: false,
            error: 'Nenhuma instância WhatsApp conectada'
          }, status: :unprocessable_entity
          return
        end

        Rails.logger.info "📤 [BULK] Instâncias disponíveis para round-robin: #{available_instances.join(', ')} (#{available_instances.size} instância(s))"

        # Processar cada lead
        leads.each do |lead|
          begin
            # Buscar o último appointment do lead
            appointment = lead.appointments.includes(:service).order('clinic_management_services.date DESC').first

            unless appointment
              error_count += 1
              errors_details << "Lead #{lead.name}: Sem appointment"
              next
            end

            # Preparar telefone
            phone = lead.phone.to_s.sub(/^55/, '')

            # ============================================================
            # SKIP LEADS ALREADY KNOWN TO HAVE NO WHATSAPP (local check)
            # ESSENTIAL: This avoids hitting the Evolution API at all for
            # leads previously confirmed without WhatsApp. The flag is set
            # by SendEvolutionMessageJob when it verifies each number.
            # ============================================================
            if lead.no_whatsapp?
              Rails.logger.info "⏭️ [BULK] #{lead.name} (#{phone}): Já marcado como sem WhatsApp - Pulando"

              skipped_no_whatsapp += 1
              skipped_leads << {
                lead_id: lead.id,
                lead_name: lead.name,
                phone: phone,
                reason: 'no_whatsapp'
              }

              # Don't advance round-robin index for skipped leads
              next
            end

            # Pick the next instance via round-robin
            # ESSENTIAL: Each lead gets the next instance in rotation so messages
            # distribute evenly across all connected WhatsApp numbers.
            instance_name = available_instances[instance_index % available_instances.size]
            instance_index += 1

            # Validar se instance_name está presente
            if instance_name.blank?
              error_count += 1
              errors_details << "Lead #{lead.name}: Instância WhatsApp não configurada"
              next
            end

            # ============================================================
            # WHATSAPP VERIFICATION: Delegated to SendEvolutionMessageJob
            # ============================================================
            # Previously, check_whatsapp_number was called HERE synchronously
            # for EVERY lead (50 leads = 50 rapid HTTP calls to Evolution API).
            # This caused the Evolution instance to disconnect due to rate
            # limiting / session overload on the WhatsApp connection.
            #
            # Now the verification happens INSIDE the job (which already has
            # this logic at perform time). The job:
            #   1. Calls check_whatsapp_number with proper spacing (45-90s between jobs)
            #   2. Marks lead as no_whatsapp if number doesn't have WhatsApp
            #   3. Broadcasts result to frontend via Turbo Stream
            #
            # This is safe because the job already handles all edge cases and
            # the delay between jobs naturally rate-limits the API calls.
            # ============================================================

            Rails.logger.info "📤 [BULK] Enfileirando #{lead.name} (#{phone}) via #{instance_name} - verificação de WhatsApp será feita no job"

            # Gerar mensagem personalizada
            message_data = get_message(message, lead, appointment.service)
            message_text = message_data[:text]
            media_details = message_data[:media]

            # Remove URL encoding
            message_text = CGI.unescape(message_text)

            # Enfileirar mensagem usando o serviço de fila
            Rails.logger.info "📤 [BULK] Enfileirando mensagem para #{lead.name} (#{phone}) na instância #{instance_name}"

            # Custom bulk interval (user-defined seconds + backend margin) or service default
            enqueue_base = bulk_base_delay
            enqueue_random = bulk_random_delay

            # ESSENTIAL: delay_multiplier = 1.0 because each instance has its own
            # independent queue. The throughput gain comes from distributing messages
            # across queues, not from reducing the interval within each queue.
            result = EvolutionMessageQueueService.enqueue_message(
              phone: phone,
              message_text: message_text,
              media_details: media_details&.stringify_keys,
              instance_name: instance_name,
              lead_id: lead.id,
              user_id: current_user.id,
              appointment_id: appointment.id,
              skip_cooldown_check: false,  # Respeitar cooldown para evitar spam em bulk
              delay_multiplier: 1.0,       # No multiplier — each queue is independent
              base_delay: enqueue_base,
              random_delay: enqueue_random
            )
            
            # Verificar se enfileiramento foi bem-sucedido
            unless result[:success]
              error_count += 1
              error_msg = result[:error] || result[:message] || 'Erro desconhecido'
              errors_details << "Lead #{lead.name}: #{error_msg}"
              Rails.logger.error "❌ [BULK] Erro ao enfileirar para #{lead.name}: #{error_msg}"
              next
            end
            
            Rails.logger.info "✅ [BULK] Mensagem enfileirada com sucesso para #{lead.name} - Job ID: #{result[:job_id]}"
            
            success_count += 1
            
            # Armazenar dados da mensagem enfileirada para o frontend
            queued_messages << {
              lead_id: lead.id,
              lead_name: lead.name,
              phone: phone,
              job_id: result[:job_id],
              delay_seconds: result[:delay_seconds],
              estimated_send_time: result[:estimated_send_time]&.iso8601,
              position_in_queue: result[:position_in_queue]
            }
            
          rescue StandardError => e
            error_count += 1
            errors_details << "Lead #{lead.name}: #{e.message}"
            Rails.logger.error "❌ [BULK] Erro ao processar lead #{lead.id}: #{e.message}"
          end
        end
        
        Rails.logger.info "✅ [BULK] Processamento concluído: #{success_count} sucessos, #{error_count} erros, #{skipped_no_whatsapp} sem WhatsApp"
        
        # Calcular estimativa total de envio
        last_message = queued_messages.max_by { |m| m[:delay_seconds] || 0 }
        total_estimated_seconds = last_message ? last_message[:delay_seconds] : 0
        
        render json: {
          success: true,
          success_count: success_count,
          error_count: error_count,
          skipped_no_whatsapp: skipped_no_whatsapp,  # Quantidade de leads pulados por não ter WhatsApp
          skipped_leads: skipped_leads,              # Detalhes dos leads pulados
          errors_details: errors_details,
          queued_messages: queued_messages,
          total_estimated_seconds: total_estimated_seconds,
          estimated_completion_time: (Time.current + total_estimated_seconds.seconds).iso8601,
          message: "Processamento concluído: #{success_count} mensagens enfileiradas#{skipped_no_whatsapp > 0 ? ", #{skipped_no_whatsapp} sem WhatsApp" : ""}#{error_count > 0 ? ", #{error_count} erros" : ""}"
        }
        
      rescue StandardError => e
        Rails.logger.error "❌ [BULK] Erro geral: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        render json: {
          success: false,
          error: "Erro ao processar envio em massa: #{e.message}"
        }, status: :internal_server_error
      end
    end

    # POST /leads/cancel_scheduled_message
    # Cancela uma mensagem programada específica
    def cancel_scheduled_message
      begin
        # Validar permissões
        unless can_use_evolution_api?
          render json: {
            success: false,
            error: 'Você não tem permissão para cancelar mensagens'
          }, status: :forbidden
          return
        end
        
        job_id = params[:job_id]
        lead_name = params[:lead_name] || 'Desconhecido'
        
        if job_id.blank?
          render json: {
            success: false,
            error: 'ID do job não informado'
          }, status: :unprocessable_entity
          return
        end
        
        Rails.logger.info "🚫 [CANCEL] Tentando cancelar job #{job_id} para #{lead_name}"
        
        # Buscar o job no GoodJob
        job = GoodJob::Job.find_by(id: job_id)
        
        if job.nil?
          render json: {
            success: false,
            error: 'Mensagem não encontrada na fila'
          }, status: :not_found
          return
        end
        
        # Verificar se o job já foi executado
        if job.finished_at.present?
          render json: {
            success: false,
            error: 'Esta mensagem já foi processada e não pode ser cancelada'
          }, status: :unprocessable_entity
          return
        end
        
        # Verificar se ainda está no futuro
        if job.scheduled_at.present? && job.scheduled_at <= Time.current
          render json: {
            success: false,
            error: 'Esta mensagem está sendo processada agora e não pode ser cancelada'
          }, status: :unprocessable_entity
          return
        end
        
        # Cancelar o job (deletar da fila)
        job.destroy!
        
        Rails.logger.info "✅ [CANCEL] Job #{job_id} cancelado com sucesso para #{lead_name}"
        
        render json: {
          success: true,
          message: "Mensagem para #{lead_name} cancelada com sucesso",
          job_id: job_id
        }
        
      rescue StandardError => e
        Rails.logger.error "❌ [CANCEL] Erro ao cancelar job: #{e.message}"
        render json: {
          success: false,
          error: "Erro ao cancelar mensagem: #{e.message}"
        }, status: :internal_server_error
      end
    end

    # GET /leads/load_scheduled_messages
    # Carrega mensagens já agendadas na fila (de envios anteriores)
    def load_scheduled_messages
      begin
        # Validar permissões
        unless can_use_evolution_api?
          render json: {
            success: false,
            error: 'Você não tem permissão para visualizar a fila'
          }, status: :forbidden
          return
        end

        # Get ALL connected instances so we show messages from every queue
        instance_names = get_bulk_instance_names

        if instance_names.blank?
          render json: {
            success: true,
            scheduled_messages: [],
            message: 'Nenhuma instância WhatsApp configurada'
          }
          return
        end

        Rails.logger.info "📋 [LOAD] Buscando mensagens agendadas para instância(s): #{instance_names.join(', ')}"

        now = Time.current

        # Build query that matches ANY connected instance queue (new model) and
        # also legacy jobs that may still exist in default queue.
        base_query = GoodJob::Job.where("serialized_params::text LIKE ?", "%SendEvolutionMessageJob%")
                                 .where("scheduled_at > ?", now)
                                 .where(finished_at: nil)

        instance_queue_names = instance_names.map { |name| EvolutionMessageQueueService.queue_name_for_instance(name) }
        legacy_like_clauses = instance_names.map { "serialized_params::text LIKE ?" }.join(' OR ')
        legacy_like_values = instance_names.map { |name| "%#{ActiveRecord::Base.sanitize_sql_like(name)}%" }

        jobs = base_query.where(
          "(queue_name IN (?)) OR (queue_name = ? AND (#{legacy_like_clauses}))",
          instance_queue_names,
          EvolutionMessageQueueService::LEGACY_QUEUE_NAME,
          *legacy_like_values
        ).order(scheduled_at: :asc)
         .limit(100)  # Limitar para performance
        
        scheduled_messages = []
        
        jobs.each do |job|
          begin
            # Extrair dados do job
            params = job.serialized_params
            arguments = params['arguments']&.first || {}
            
            phone = arguments['phone']
            lead_id = arguments['lead_id']
            
            # Buscar nome do lead se possível
            lead_name = 'Desconhecido'
            if lead_id.present?
              lead = Lead.find_by(id: lead_id)
              lead_name = lead&.name || "Lead ##{lead_id}"
            end
            
            scheduled_messages << {
              job_id: job.id,
              lead_id: lead_id,
              lead_name: lead_name,
              phone: phone || 'N/A',
              estimated_send_time: job.scheduled_at&.iso8601,
              delay_seconds: ((job.scheduled_at - now) rescue 0).to_i,
              created_at: job.created_at&.iso8601
            }
          rescue => e
            Rails.logger.warn "⚠️ [LOAD] Erro ao processar job #{job.id}: #{e.message}"
          end
        end
        
        Rails.logger.info "✅ [LOAD] Encontradas #{scheduled_messages.length} mensagens agendadas"
        
        render json: {
          success: true,
          scheduled_messages: scheduled_messages,
          total_count: scheduled_messages.length,
          instance_names: instance_names
        }

      rescue StandardError => e
        Rails.logger.error "❌ [LOAD] Erro ao carregar mensagens: #{e.message}"
        render json: {
          success: false,
          error: "Erro ao carregar mensagens: #{e.message}"
        }, status: :internal_server_error
      end
    end

    # DELETE /leads/clear_all_scheduled_messages
    # Limpa TODAS as mensagens agendadas na fila
    def clear_all_scheduled_messages
      begin
        # Validar permissões
        unless can_use_evolution_api?
          render json: {
            success: false,
            error: 'Você não tem permissão para limpar a fila'
          }, status: :forbidden
          return
        end

        # Get ALL connected instances so we clear messages from every queue
        instance_names = get_bulk_instance_names

        if instance_names.blank?
          render json: {
            success: true,
            cancelled_count: 0,
            message: 'Nenhuma instância WhatsApp configurada'
          }
          return
        end

        Rails.logger.info "🗑️ [CLEAR] Limpando TODAS as mensagens agendadas para instância(s): #{instance_names.join(', ')}"

        now = Time.current

        # Buscar TODOS os jobs pendentes da fila para TODAS as instâncias do usuário.
        # Inclui filas dedicadas por instância e fallback para jobs legacy na default.
        base_query = GoodJob::Job.where("serialized_params::text LIKE ?", "%SendEvolutionMessageJob%")
                                 .where("scheduled_at > ?", now)
                                 .where(finished_at: nil)

        instance_queue_names = instance_names.map { |name| EvolutionMessageQueueService.queue_name_for_instance(name) }
        legacy_like_clauses = instance_names.map { "serialized_params::text LIKE ?" }.join(' OR ')
        legacy_like_values = instance_names.map { |name| "%#{ActiveRecord::Base.sanitize_sql_like(name)}%" }

        jobs = base_query.where(
          "(queue_name IN (?)) OR (queue_name = ? AND (#{legacy_like_clauses}))",
          instance_queue_names,
          EvolutionMessageQueueService::LEGACY_QUEUE_NAME,
          *legacy_like_values
        )
        
        total_count = jobs.count
        
        if total_count == 0
          render json: {
            success: true,
            cancelled_count: 0,
            message: 'Nenhuma mensagem na fila para cancelar'
          }
          return
        end
        
        # Deletar todos os jobs
        deleted_count = jobs.destroy_all.count
        
        Rails.logger.info "✅ [CLEAR] #{deleted_count} mensagens removidas da fila"
        
        render json: {
          success: true,
          cancelled_count: deleted_count,
          message: "#{deleted_count} mensagens foram removidas da fila"
        }
        
      rescue StandardError => e
        Rails.logger.error "❌ [CLEAR] Erro ao limpar fila: #{e.message}"
        render json: {
          success: false,
          error: "Erro ao limpar fila: #{e.message}"
        }, status: :internal_server_error
      end
    end

    private
    
    # Returns a single instance name for individual message sends.
    # Priority: 1) Bulk instances (round-robin), 2) Referral instances, 3) Account instance 2.
    # NOTE: For bulk sends, use get_bulk_instance_names instead to get the full
    # list and distribute manually — calling this method N times would advance
    # the round-robin counter via mark_as_used! causing uneven distribution.
    def get_evolution_instance_name
      if referral?(current_user)
        referral = user_referral
        # Use round-robin instance selection if available
        referral&.next_evolution_instance_name
      else
        account = if respond_to?(:current_account) && current_account.present?
          current_account
        else
          Account.first
        end

        # ESSENTIAL: Prioritize bulk instances for non-referral sends.
        # This prevents using the clinic WhatsApp (instance_2) for bulk messaging.
        # Only used when the bulk_evolution feature is enabled for this account.
        if account&.bulk_evolution_enabled?
          bulk_instance = BulkEvolutionInstance.next_for_sending(account.id)
          if bulk_instance
            bulk_instance.mark_as_used!
            return bulk_instance.instance_name
          end
        end

        account&.evolution_instance_name_2
      end
    end

    # Returns ALL connected instance names for round-robin distribution in bulk sends.
    # For referrals: returns all connected + active instances (e.g. ["inst_A", "inst_B"])
    # For non-referrals: returns the single Account instance as a one-element array.
    #
    # ESSENTIAL: This method does NOT call mark_as_used! — the caller controls
    # round-robin index manually so skipped leads don't waste slots.
    #
    # @return [Array<String>] Array of instance names, never empty if user can send
    # @example
    #   get_bulk_instance_names
    #   # => ["referral_inst_1", "referral_inst_2"]  (referral with 2 instances)
    #   # => ["account_inst_2"]                       (non-referral)
    def get_bulk_instance_names
      if referral?(current_user)
        referral = user_referral
        return [] unless referral

        names = referral.connected_instance_names
        # connected_instance_names already includes legacy single instance if connected
        names.presence || []
      else
        account = if respond_to?(:current_account) && current_account.present?
          current_account
        else
          Account.first
        end

        # ESSENTIAL: Prioritize dedicated bulk instances over clinic instance (instance_2).
        # Using instance_2 for bulk messaging risks WhatsApp ban on the clinic number.
        # Bulk instances are separate numbers specifically for mass sending.
        # When bulk_evolution_enabled but no bulk instances configured, fall back to
        # instance_2 so bulk send still works until user configures dedicated connections.
        if account&.bulk_evolution_enabled?
          bulk_names = BulkEvolutionInstance.connected_instance_names(account.id)
          return bulk_names if bulk_names.present?
        end

        # Fallback: instance_2 (clinic) — used when bulk disabled or no bulk instances
        instance = account&.evolution_instance_name_2
        instance.present? ? [instance] : []
      end
    end

    # Decides how to handle the synchronous WhatsApp check in bulk mode.
    # - :confirmed_no_whatsapp => API answered successfully and explicitly said no.
    # - :api_error             => API check failed; do not drop queue slot.
    # - :valid_or_unknown      => proceed with enqueue (job re-validates before send).
    def bulk_whatsapp_check_outcome(whatsapp_check)
      exists_value = whatsapp_check[:exists]
      has_error = whatsapp_check[:error].present?

      return :confirmed_no_whatsapp if exists_value == false && !has_error
      return :api_error if has_error

      :valid_or_unknown
    end

    # Returns the delay multiplier based on number of connected instances.
    # With 2 instances: delay is halved, with 3: divided by 3, etc.
    # NOTE: NOT used in send_bulk_messages because all messages in a batch go
    # to the same instance. Only useful for individual sends where each request
    # picks a different instance via round-robin.
    def get_evolution_delay_multiplier
      if referral?(current_user)
        referral = user_referral
        referral&.evolution_delay_multiplier || 1.0
      else
        # ESSENTIAL: Use bulk instance delay multiplier when bulk instances exist.
        account = if respond_to?(:current_account) && current_account.present?
          current_account
        else
          Account.first
        end

        if account&.bulk_evolution_enabled? && BulkEvolutionInstance.any_connected?(account.id)
          BulkEvolutionInstance.delay_multiplier(account.id)
        else
          1.0
        end
      end
    end

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

    # Retorna o escopo base de leads ausentes, sem diferenciação de usuário.
    # Service location filter passed into base query for DB-level efficiency (no extra filter step).
    def base_absent_leads_scope
      absent_threshold_date = 1.day.ago.to_date
      loc_filter = current_account&.multi_service_locations_enabled? ? current_service_location_id.to_s : nil
      fetch_leads_by_appointment_condition(
        'clinic_management_appointments.attendance = ? AND clinic_management_services.date < ?',
        false,
        absent_threshold_date,
        service_location_filter: loc_filter
      )
    end

    # Applies service_location filter to scope (main_svc already joined). Used inside fetch_leads_by_appointment_condition.
    def apply_service_location_scope(scope, loc_filter)
      return scope if loc_filter.nil?
      case loc_filter.to_s
      when "all"
        scope.where("main_svc.service_location_id IS NOT NULL")
      when ""
        scope.where("main_svc.service_location_id IS NULL")
      else
        scope.where("main_svc.service_location_id = ?", loc_filter)
      end
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
      when "wrong_phone"
        scope.where(wrong_phone: true)
      when "visible"
        scope.where(
          hidden_from_absent: [false, nil],
          no_interest: [false, nil],
          wrong_phone: [false, nil]
        )
      else
        # Default: sempre excluir leads com status especial da listagem principal
        scope.where(
          hidden_from_absent: [false, nil],
          no_interest: [false, nil],
          wrong_phone: [false, nil]
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
      cutoff_date = 180.days.ago.to_date
      
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
        
        # Construir conteúdo do paciente com responsável integrado
        patient_content = render_to_string(
          partial: "clinic_management/leads/patient_name_with_edit_button", 
          locals: { invitation: last_invitation }
        ).html_safe
        
        # Adicionar responsável se for diferente do paciente
        responsible_name = responsible_content(last_invitation)
        if responsible_name.present?
          patient_content += "<div class='text-sm text-gray-600 mt-1'>Resp: #{responsible_name}</div>".html_safe
        end
        
        # Construir conteúdo da primeira coluna (Ordem + Checkbox se Evolution API ativo)
        ordem_content = if can_use_evolution_api?
          # Checkbox + número da ordem
          "<div class='flex items-center justify-center gap-2'>" \
          "<input type='checkbox' " \
          "class='w-5 h-5 text-blue-600 border-gray-300 rounded focus:ring-2 focus:ring-blue-500 cursor-pointer' " \
          "data-bulk-message-target='leadCheckbox' " \
          "data-lead-id='#{lead.id}' " \
          "data-lead-phone='#{lead.phone}' " \
          "data-lead-name='#{lead.name}' " \
          "data-action='change->bulk-message#updateCounter' />" \
          "<span class='font-semibold'>#{index + 1}</span>" \
          "</div>"
        else
          # Apenas o número (convertido para string)
          (index + 1).to_s
        end
        
        [
          {
            header: "Ordem", 
            content: ordem_content.to_s.html_safe, 
            row_id: "lead-row-#{lead.id}",  # ID único para highlight
            row_class: ""  # Classe será manipulada via JS para highlight
          },
          {
            header: "Paciente", 
            content: patient_content, 
            class: "nowrap size_20 patient-name" 
          },
          # Status column with separated order information
          {header: "Status", content: status_content.to_s.html_safe, class: "!min-w-[300px] size_20 " + helpers.status_class(last_appointment)},
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
      last_appointment.present? ? helpers.link_to("#{invite_day(last_appointment).to_s.html_safe}", service_path(last_appointment.service), class: "text-blue-500 hover:text-blue-700", target: "_blank").html_safe : ""
    end
    
    
      def responsible_content(invite)
        if invite.present?
          (invite.lead.name != invite.patient_name) ? invite.lead.name : ""
        else
          ""
        end
      end

      # Fetches leads by appointment condition. Uses subquery for exclusions (no pluck) for scale.
      # @param service_location_filter [nil, String] nil = no filter; "" = internal; "all" = externals; id = specific
      def fetch_leads_by_appointment_condition(query_condition, value, date = nil, service_location_filter: nil)
        one_year_ago = Date.current - 1.year

        # 1. Subquery for leads who attended in last year — NOT pluck (avoids loading 10k+ IDs into memory).
        # Database handles NOT IN (SELECT ...) efficiently with indexes.
        excluded_subquery = ClinicManagement::Appointment
          .joins(:service)
          .where('clinic_management_appointments.attendance = ? AND clinic_management_services.date >= ?', true, one_year_ago)
          .select(:lead_id)

        # 2. Base query with joins. Service location filter applied in same WHERE for planner optimization.
        base_query = ClinicManagement::Lead
          .joins("INNER JOIN clinic_management_appointments AS main_apt ON clinic_management_leads.last_appointment_id = main_apt.id")
          .joins("INNER JOIN clinic_management_services AS main_svc ON main_apt.service_id = main_svc.id")
          .joins("LEFT JOIN clinic_management_lead_interactions AS latest_interaction ON clinic_management_leads.id = latest_interaction.lead_id AND latest_interaction.occurred_at = (SELECT MAX(li2.occurred_at) FROM clinic_management_lead_interactions li2 WHERE li2.lead_id = clinic_management_leads.id)")
          .joins("LEFT JOIN users AS interaction_user ON latest_interaction.user_id = interaction_user.id")
          .select(
            'clinic_management_leads.*',
            'main_svc.date as service_date',
            'main_apt.last_message_sent_at',
            'main_apt.last_message_sent_by',
            'main_apt.id as current_appointment_id',
            'latest_interaction.occurred_at as latest_interaction_at',
            'interaction_user.name as latest_interaction_by',
            'COALESCE(latest_interaction.occurred_at, main_apt.last_message_sent_at) as unified_last_contact_at',
            'COALESCE(interaction_user.name, main_apt.last_message_sent_by) as unified_last_contact_by'
          )
          .where.not(id: excluded_subquery)

        # 3. Service location filter — applied in base query so planner can use service_location_id index early.
        base_query = apply_service_location_scope(base_query, service_location_filter)

        # 4. Attendance/date conditions
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
        loc_filter = current_account&.multi_service_locations_enabled? ? current_service_location_id.to_s : nil
        leads = fetch_leads_by_appointment_condition(
          'clinic_management_appointments.attendance = ?',
          false,
          nil,
          service_location_filter: loc_filter
        )
        
        if params[:year].present? && params[:month].present?
          start_date = Date.new(params[:year].to_i, params[:month].to_i, 1)
          end_date = start_date.end_of_month
          leads = leads.where('main_svc.date BETWEEN ? AND ?', start_date, end_date)
        end

        leads
      end

      def generate_filename
        month_name = I18n.t("date.month_names")[params[:month].to_i]
        "leads_#{month_name.downcase}_#{params[:year]}.csv"
      end

      # Returns services available for rescheduling. Includes service_location for multi-location filtering.
      # ESSENTIAL: When multi_service_locations_enabled, filter by navbar location. When navbar has
      # specific location or Interno, Local select is hidden — so we pre-filter here.
      def available_services(service)
        scope = ClinicManagement::Service.where(canceled: [nil, false]).where("date >= ?", Date.current).order(date: :asc)
        scope = scope.where.not(id: service.id) if service&.id.present?
        if current_account&.multi_service_locations_enabled?
          scope = scope.merge(ClinicManagement::Service.for_location(current_service_location_id.to_s))
        end
        scope.includes(:service_location)
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
            duration_hours: 8
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
      
      # Gera mensagem personalizada com substituições de placeholders
      # Copiado do LeadMessagesController para uso no envio em massa
      def get_message(message, lead, service)
        Rails.logger.debug "Entering get_message method"
        Rails.logger.debug "Message: #{message.inspect}"
        Rails.logger.debug "Lead: #{lead.inspect}"
        Rails.logger.debug "Service: #{service.inspect}"

        return { text: "", media: nil } if message.nil?
        
        result = message.text
        Rails.logger.debug "Initial result: #{result.inspect}"

        return { text: "", media: nil } if result.nil?

        # Escolha aleatória de segmentos de texto
        result = result.gsub(/\[.*?\]/) do |match|
          options = match.tr('[]', '').split('|')
          options.sample
        end

        # Substituições de texto padrão
        result = result.gsub("{PRIMEIRO_NOME_PACIENTE}", lead.name.split(" ").first)
                 .gsub("{NOME_COMPLETO_PACIENTE}", lead.name)
                 .gsub("\n", "%0A")
                 .gsub("\r\n", "%0A")

        if service.present?
          # Substituições relacionadas ao serviço
          result = result.gsub("{DIA_SEMANA_ATENDIMENTO}", I18n.l(service&.date, format: "%A").to_s)
                         .gsub("{MES_DO_ATENDIMENTO}", I18n.l(service.date, format: "%B").to_s)
                         .gsub("{DIA_ATENDIMENTO_NUMERO}", service&.date&.strftime("%d").to_s)
                         .gsub("{HORARIO_DE_INICIO}", service.start_time.strftime("%H:%M").to_s)
                         .gsub("{HORARIO_DE_TERMINO}", service.end_time.strftime("%H:%M").to_s)
                         .gsub("{DATA_DO_ATENDIMENTO}", service&.date&.strftime("%d/%m/%Y").to_s)
        end

        # Extract media details (both from attached files and URL-based media)
        media_details = extract_media_details(message, result)
        
        # Remove URL-based media tags from final message if present
        final_message = result.gsub(/\[url=".*?"\s+legenda=".*?"\s+tipo=".*?"\]/, '')

        Rails.logger.debug "Final result: #{final_message.inspect}"
        Rails.logger.debug "Media details: #{media_details.inspect}"
        
        { text: final_message.strip, media: media_details }
      end
      
      # Extract media details from both attached files and URL-based media in text
      def extract_media_details(message, text)
        # Priority 1: Check for attached file
        if message.has_media?
          return {
            url: message.media_url,
            caption: message.media_caption.present? ? message.media_caption : '',
            type: message.whatsapp_media_type
          }
        end
        
        # Priority 2: Check for URL-based media in text (legacy support)
        media_regex = /\[url="(?<url>[^"]+)" legenda="(?<caption>[^"]*)" tipo="(?<type>[^"]+)"\]/
        match = text.match(media_regex)
        if match
          return {
            url: match[:url],
            caption: match[:caption],
            type: match[:type]
          }
        end
        
        # No media found
        nil
      end
  end
end