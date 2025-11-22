module ClinicManagement
  class InvitationsController < ApplicationController
    before_action :set_invitation, only: %i[ show edit update destroy ]
    skip_before_action :redirect_referral_users, only: [:new, :create, :update, :index, :edit_patient_name, :update_patient_name, :check_existing_phone]
    include GeneralHelper

    # GET /invitations
    def index
      @referrals = Referral.all
      
      # Get month/year filter params (default to current month)
      @selected_month = params[:month]&.to_i || Date.current.month
      @selected_year = params[:year]&.to_i || Date.current.year
      
      # Calculate date range for the selected month
      start_date = Date.new(@selected_year, @selected_month, 1)
      end_date = start_date.end_of_month
      
      # Check if current user is a referral (restrict to own data)
      @is_referral_user = referral?(current_user)
      @current_user_referral = nil
      
      if @is_referral_user
        # Referral users can only see their own data
        user_referral = helpers.user_referral
        @current_user_referral = user_referral
        
        @invitations = Invitation.where(referral_id: user_referral.id)
                                 .where(date: start_date..end_date)
                                 .includes(:lead, :region, appointments: :service)
                                 .order(created_at: :desc)
        @appointments = fetch_reschedules_for_referral(user_referral.id, start_date, end_date)
      else
        # Managers and owners can see all or filter by referral
        if params[:referral_id].present?
          @invitations = Invitation.where(referral_id: params[:referral_id])
                                   .where(date: start_date..end_date)
                                   .includes(:lead, :region, appointments: :service)
                                   .order(created_at: :desc)
          @appointments = fetch_reschedules_for_referral(params[:referral_id], start_date, end_date)
        else
          @invitations = Invitation.where(date: start_date..end_date)
                                   .includes(:lead, :region, appointments: :service)
                                   .order(created_at: :desc)
          @appointments = fetch_all_reschedules(start_date, end_date)
        end
      end
      
      # Exclude invitations that are actually reschedules to avoid duplication
      reschedule_invitation_ids = @appointments.pluck(:invitation_id)
      @invitations = @invitations.where.not(id: reschedule_invitation_ids)

      # Prepare available months/years for the filter
      @available_dates = prepare_available_months_years(@is_referral_user ? @current_user_referral&.id : nil)
      
      # Fetch interactions for the period
      @interactions = LeadInteraction.where(occurred_at: start_date.beginning_of_day..end_date.end_of_day)

      # Prepare data for the new elegant table
      @invitations_data = prepare_invitations_reschedules_data(@invitations, @appointments, @interactions)
      
      # Calculate period totals for display
      @total_invitations = @invitations.count
      @total_reschedules = @appointments.count
    end

    def performance_report
      @report_data = generate_performance_report
    end
    
    # GET /invitations/1
    def show
    end

    # GET /invitations/new
    def new
      @services_list = next_services
      @regions = Region.all.order(:name)
      @invitation = Invitation.new
      @appointment = @invitation.appointments.build
      @lead = @invitation.build_lead
      @referrals = Referral.all    
      begin
        @today_invitations = helpers.user_referral.invitations.where('created_at >= ?', Date.current.beginning_of_day).limit(100)
        @today_invitations = @today_invitations.map do |invitation|
          service = invitation.appointments.last&.service
          [invitation, service] if service
        end.compact
      rescue
        @today_invitations = nil
      end
    end

    # GET /invitations/1/edit
    def edit
    end

    def create
      begin
        ActiveRecord::Base.transaction do
          case params[:phone_action]
          when 'associate'
            @lead = associate_with_existing_lead(invitation_params)
          when 'transfer'
            @lead = transfer_phone_to_new_lead(invitation_params)
          else
            @lead = check_existing_leads(invitation_params)
          end
          
          @invitation = @lead.invitations.build(invitation_params.except(:lead_attributes, :appointments_attributes))
          @lead.update!(name: @invitation.patient_name) if @lead.name.blank?
          puts @lead.errors.full_messages
          appointment_params = invitation_params[:appointments_attributes]["0"].merge({status: "agendado", lead: @lead})
          existing_appointment = already_schedule_this_patient?(@invitation, appointment_params[:service_id])   
          
          if existing_appointment
            @lead.errors.add(:base, "Este paciente chamado #{@lead.name} já está agendado para este atendimento.")
            @invitation.destroy
            raise ActiveRecord::RecordInvalid.new(@lead)
          else
            @appointment = @invitation.appointments.build(appointment_params)
            @appointment.referral_code = @invitation&.referral&.code
            @appointment.registered_by_user_id = current_user&.id
            @appointment.save!
          end
        end
        @lead.update(last_appointment_id: @appointment.id)
        puts @lead.errors.full_messages
        render_turbo_stream
      rescue ActiveRecord::RecordInvalid => exception
        render_validation_errors(exception)
      end
    end

    def already_schedule_this_patient?(invitation, service_id)
      phone = invitation.lead.phone
      patient_first_name = invitation.patient_name.split.first
      # check if this service has any appointment with this patient first name and phone
      ClinicManagement::Appointment
        .joins(:service, :lead, :invitation)
        .where(
          clinic_management_services: { id: service_id },
          clinic_management_leads: { phone: phone },
          clinic_management_invitations: { patient_name: patient_first_name }
        ).exists?
    end
    
    def new_patient_fitted
      @service = Service.find(params[:service_id])
      # @services = Service.all    
      @invitation = Invitation.new
      @appointment = @invitation.appointments.build
      @lead = @invitation.build_lead
      @referrals = Referral.all    
    end

    def create_patient_fitted
      begin
        ActiveRecord::Base.transaction do
          # Aplicar a mesma lógica de verificação de telefone
          case params[:phone_action]
          when 'associate'
            @lead = associate_with_existing_lead(invitation_params)
          when 'transfer'
            @lead = transfer_phone_to_new_lead(invitation_params)
          else
            @lead = check_existing_leads(invitation_params)
          end
          
          @invitation = @lead.invitations.new(invitation_params.except(:lead_attributes, :appointments_attributes, :recapture_origin, :recapture_actions, :recapture_screenshots, :recapture_description, :recapture_description_extra))       
          @invitation.region = set_local_region
          @invitation.save!
          @lead.update!(name: @invitation.patient_name) if @lead.name.blank?    
          
          appointment_params = invitation_params[:appointments_attributes]["0"].merge({status: "agendado", lead: @lead})
          existing_appointment = already_schedule_this_patient?(@invitation, appointment_params[:service_id])
          
          if existing_appointment
            @lead.errors.add(:base, "Este paciente chamado #{@lead.name} já está agendado para este atendimento.")
            raise ActiveRecord::RecordInvalid.new(@lead)
          else
            # Construir appointment
            @appointment = @invitation.appointments.build(appointment_params)
            @appointment.referral_code = @invitation&.referral&.code
            @appointment.registered_by_user_id = current_user&.id
            
            # Processar dados de recaptura (opcional)
            if invitation_params[:recapture_origin].present?
              @appointment.recapture_origin = invitation_params[:recapture_origin]
              @appointment.recapture_actions = invitation_params[:recapture_actions]&.reject(&:blank?) || []
              @appointment.recapture_by_user_id = current_user&.id
              
              # Construir descrição
              desc_parts = []
              desc_parts << invitation_params[:recapture_description] if invitation_params[:recapture_description].present?
              desc_parts << invitation_params[:recapture_description_extra] if invitation_params[:recapture_description_extra].present?
              @appointment.recapture_description = desc_parts.join(' | ') if desc_parts.any?
            end
            
            # Salvar SEM validação primeiro para gerar ID e permitir anexos
            @appointment.save!(validate: false)
            
            # Anexar screenshots DEPOIS de ter ID (necessário dentro de transaction)
            if invitation_params[:recapture_screenshots].present?
              @appointment.recapture_screenshots.attach(invitation_params[:recapture_screenshots])
            end
            
            # Verificar se tem attachments (via parâmetro, pois .attached? pode ser false dentro de transaction)
            has_attachments = invitation_params[:recapture_screenshots].present?
            
            # Validar manualmente APENAS se for esforço ativo (não chamar .valid? para evitar problema com ActiveStorage em transaction)
            if @appointment.recapture_origin == 'active_effort'
              # Verificar ações
              if @appointment.recapture_actions.blank? || @appointment.recapture_actions.reject(&:blank?).empty?
                @appointment.errors.add(:recapture_actions, "deve ter pelo menos uma ação selecionada")
                raise ActiveRecord::RecordInvalid.new(@appointment)
              end
              
              # Screenshots agora são opcionais - não validar mais
              
              # Para active_effort, NÃO chamar .valid? pois já validamos tudo manualmente
            else
              # Para orgânico ou sem origem, validar normalmente
              unless @appointment.valid?
                raise ActiveRecord::RecordInvalid.new(@appointment)
              end
            end
          end
        end
        
        @lead.update(last_appointment_id: @appointment.id)
        
        if @appointment.service.date == Date.current
          redirect_to index_today_path
        elsif @appointment.service.date == Service.where('date > ?', Date.current).order(:date).pluck(:date).first
          redirect_to index_next_path
        else
          redirect_to @appointment.service
        end
      rescue ActiveRecord::RecordInvalid => exception
        render_validation_errors(exception)
      end
    end
    

    # PATCH/PUT /invitations/1
    def update
      if @invitation.update(invitation_params)
        redirect_to @invitation, notice: "Invitation was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /invitations/1
    def destroy
      @invitation.destroy
      redirect_to new_invitation_url, notice: "Invitation was successfully destroyed."
    end

    def edit_patient_name
      @invitation = Invitation.find(params[:id])
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "patient-name-#{@invitation.id}", 
            partial: "patient_name_form", 
            locals: { invitation: @invitation }
          )
        end
      end
    end

    def update_patient_name
      @invitation = Invitation.find(params[:id])
      
      if @invitation.update(patient_name: params[:patient_name])
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "patient-name-#{@invitation.id}", 
              partial: "clinic_management/leads/patient_name_with_edit_button", 
              locals: { invitation: @invitation, count: params[:count] }
            )
          end
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "patient-name-#{@invitation.id}", 
              partial: "patient_name_form", 
              locals: { invitation: @invitation, error: "Nome não pode ficar em branco" }
            )
          end
        end
      end
    end

    def check_existing_phone
      phone = params[:phone]
      
      if phone.present? && phone.length >= 10
        # Sanitizar o telefone para busca (remover caracteres da máscara)
        clean_phone = phone.gsub(/\D/, '')
        existing_lead = ClinicManagement::Lead.find_by(phone: clean_phone)
        
        if existing_lead.present?
          # Buscar dados do lead existente
          last_invitation = existing_lead.invitations.last
          last_appointment = existing_lead.appointments.last
          
          render json: {
            exists: true,
            lead: {
              id: existing_lead.id,
              name: existing_lead.name,
              phone: existing_lead.phone,
              address: existing_lead.address,
              last_patient_name: last_invitation&.patient_name,
              last_service_date: last_appointment&.service&.date&.strftime("%d/%m/%Y"),
              invitations_count: existing_lead.invitations.count,
              appointments_count: existing_lead.appointments.count
            }
          }
        else
          render json: { exists: false }
        end
      else
        render json: { exists: false }
      end
    end

    private

    def generate_performance_report
      start_date = Invitation.minimum(:date)
      end_date = Invitation.maximum(:date)
    
      report_data = []
    
      (start_date..end_date).group_by { |date| [date.year, date.month] }.each do |(year, month), dates|
        month_start = dates.first
        month_end = dates.last
    
        month_invitations = Invitation.where(date: month_start..month_end).includes(:referral, :lead)
    
        referral_data = month_invitations.group_by(&:referral).map do |referral, invitations|
          converted_leads = invitations.select { |invitation| invitation.lead&.converted? }.size
          conversion_rate = converted_leads.to_f / invitations.size * 100
    
          delivered_orders = referral.commissions.where(created_at: month_start..month_end)
                                                  .joins(:order)
                                                  .where(orders: { delivery_status: 'DELIVERED' })
                                                  .count
    
          {
            referral: referral.name,
            days_worked: invitations.map(&:date).uniq.size,
            invited: invitations.size,
            conversions: converted_leads,
            conversion_rate: conversion_rate,
            conversion_class: calculate_conversion_class(conversion_rate),
            delivered_orders: delivered_orders
          }
        end
    
        report_data << {
          period: "#{I18n.t('date.month_names')[month]} / #{year}",
          referral_data: referral_data
        }
      end
    
      report_data
    end


    def check_existing_leads(params)
      phone = params.dig(:lead_attributes, :phone)
      patient_name = params[:patient_name]
      lead_name = params.dig(:lead_attributes, :name)
      
      return Lead.create!(params[:lead_attributes]) if phone.blank?
      
      # Sanitizar o telefone para busca (remover caracteres da máscara)
      clean_phone = phone.gsub(/\D/, '')
      
      existing_lead = Lead.find_by(phone: clean_phone)
      
      if existing_lead.present?
        Rails.logger.info "Usando lead existente (ID: #{existing_lead.id}) para telefone: #{phone}"
        
        # Auto-merge de informações
        merge_lead_information(existing_lead, params, patient_name, lead_name)
        
        # Log da ação para auditoria
        Rails.logger.info "Lead #{existing_lead.id} atualizado com novas informações do convite"
        
        return existing_lead
      else
        # Sanitizar os parâmetros do lead antes de criar
        lead_params = params[:lead_attributes].dup
        lead_params[:phone] = clean_phone if lead_params[:phone].present?
        
        Lead.create!(lead_params)
      end
    end

    def merge_lead_information(existing_lead, params, patient_name, lead_name)
      updates = {}
      
      # Merge de nome (prioriza o nome mais completo)
      new_name = lead_name.presence || patient_name
      if should_update_name?(existing_lead.name, new_name)
        updates[:name] = new_name
      end
      
      # Merge de endereço
      new_address = params.dig(:lead_attributes, :address)
      if existing_lead.address.blank? && new_address.present?
        updates[:address] = new_address
      end
      
      # Merge de coordenadas
      new_latitude = params.dig(:lead_attributes, :latitude)
      new_longitude = params.dig(:lead_attributes, :longitude)
      
      if existing_lead.latitude.blank? && new_latitude.present?
        updates[:latitude] = new_latitude
      end
      
      if existing_lead.longitude.blank? && new_longitude.present?
        updates[:longitude] = new_longitude
      end
      
      existing_lead.update!(updates) if updates.any?
    end

    def should_update_name?(existing_name, new_name)
      return true if existing_name.blank? && new_name.present?
      return false if new_name.blank?
      
      # Atualiza se o novo nome é mais completo (mais palavras)
      existing_name.split.length < new_name.split.length
    end
    
    def set_local_region
      region = Region.find_by(name: "Local")
      unless region.present?
        region = Region.create(name: "Local")
      end
      region
    end

    def render_turbo_stream
      invitation_list_locals = {
        invitation: @invitation, 
        appointment: @appointment,
        service: @appointment.service.id,
        referral: @invitation.referral.id
        }
      before_attributes = {
        referral: @invitation.referral.id,
        region: @invitation.region.id,
        service: @appointment.service.id,
        date: @invitation.date,
        services_list: next_services
      }
      new_form_sets
      new_form_locals = { 
          invitation: @invitation, 
          referrals: Referral.all, 
          regions: Region.all
      }
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.prepend("invitations_list", partial: "invitation", locals: invitation_list_locals) +
                               turbo_stream.replace("new_invitation", partial: "form", locals: new_form_locals.merge(before_attributes) ) + 
                               turbo_stream.update("validation", "")
        end
      end
    end
    
    def render_validation_errors(exception)
      validation_content = exception.record.errors.full_messages.join(', ')
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("validation", validation_content)
        end
      end
    end

      def new_form_sets
        @services = Service.all    
        @regions = Region.all
        @invitation = Invitation.new
        @appointment = @invitation.appointments.build
        @lead = @invitation.build_lead
        @referrals = Referral.all
      end


      def process_invitations_data(invitations)
        rows = []
        invitations = invitations.where.not(date: nil)
        start_date = invitations.map(&:date).min
        end_date = invitations.map(&:date).max
      
        (start_date..end_date).reverse_each do |date|
          date_invitations = invitations.select { |invite| invite.date == date }
      
          if date_invitations.any?
            rows << [{header: "", content: helpers.show_week_day(date.strftime("%A")) + ", " + date.strftime("%d/%m/%Y"), colspan: 4, class: "bg-gray-100 font-bold"}]
      
            referral_invitations = date_invitations.group_by { |invite| invite.referral }
            sorted_referral_invitations = referral_invitations.sort_by { |referral, invites| -invites.size }
      
            sorted_referral_invitations.each do |referral, referral_invitations|
              lead_invitations = referral_invitations.group_by { |invite| invite.lead }
              patient_links = lead_invitations.map do |lead, invites|
                count = lead.appointments.count
                patient_link(invites.first, count)
              end
      
              rows << [
                {header: "Indicador", content: referral&.name},
                {header: "Qtd de convites", content: referral_invitations.size},
                {header: "Convites", content: patient_links.join(", ").html_safe},
                {header: "Regiões", content: referral_invitations.map { |invite| invite&.region&.name }.uniq.join(", ")},
                {header: "", content: ""}
              ]
            end
          else
            rows << [{header: "", content: helpers.show_week_day(date.strftime("%A")) + ", " + date.strftime("%d/%m/%Y"), colspan: 4, class: "bg-gray-100 font-bold"}]
            rows << [
              {header: "Indicador", content: ""},
              {header: "Qtd de convites", content: ""},
              {header: "Convites", content: "Sem lançamentos"},
              {header: "Regiões", content: ""},
              {header: "", content: ""}
            ]
          end
        end
      
        rows
      end

      def process_invitations_and_appointments_data(invitations, appointments)
        rows = []
        
        # Get date range from both invitations and appointments (when they were made, not scheduled for)
        invitation_dates = invitations.where.not(date: nil).map(&:date).compact
        appointment_dates = appointments.map { |apt| apt.created_at&.to_date }.compact
        all_dates = (invitation_dates + appointment_dates).uniq.sort
        
        return rows if all_dates.empty?
        
        start_date = all_dates.min
        end_date = all_dates.max
      
        (start_date..end_date).reverse_each do |date|
          date_invitations = invitations.select { |invite| invite.date == date }
          date_appointments = appointments.select { |apt| apt.created_at&.to_date == date }
      
          if date_invitations.any? || date_appointments.any?
            rows << [{header: "", content: helpers.show_week_day(date.strftime("%A")) + ", " + date.strftime("%d/%m/%Y"), colspan: 5, class: "bg-gray-100 font-bold"}]
      
            # Group invitations by referral
            referral_invitations = date_invitations.group_by { |invite| invite.referral }
            
            # Group appointments by referral (through invitation)
            referral_appointments = date_appointments.group_by do |apt|
              apt.invitation&.referral
            end
            
            # Combine all referrals from both groups
            all_referrals = (referral_invitations.keys + referral_appointments.keys).compact.uniq
            
            sorted_referrals = all_referrals.sort_by do |referral|
              invitation_count = referral_invitations[referral]&.size || 0
              appointment_count = referral_appointments[referral]&.size || 0
              -(invitation_count + appointment_count)
            end
      
            sorted_referrals.each do |referral|
              r_invitations = referral_invitations[referral] || []
              r_appointments = referral_appointments[referral] || []
              
              # Build invitation patient links
              invitation_patient_links = []
              if r_invitations.any?
                lead_invitations = r_invitations.group_by { |invite| invite.lead }
                invitation_patient_links = lead_invitations.map do |lead, invites|
                  count = lead.appointments.count
                  patient_link(invites.first, count)
                end
              end
              
              # Build appointment patient links (remarcações)
              appointment_patient_links = []
              if r_appointments.any?
                lead_appointments = r_appointments.group_by { |apt| apt.lead }
                appointment_patient_links = lead_appointments.map do |lead, apts|
                  appointment_link(apts.first)
                end
              end
      
              rows << [
                {header: "Indicador", content: referral&.name},
                {header: "Qtd de convites", content: r_invitations.size},
                {header: "Convites", content: invitation_patient_links.join(", ").html_safe},
                {header: "Qtd de remarcações", content: r_appointments.size},
                {header: "Remarcações", content: appointment_patient_links.join(", ").html_safe}
              ]
            end
          else
            rows << [{header: "", content: helpers.show_week_day(date.strftime("%A")) + ", " + date.strftime("%d/%m/%Y"), colspan: 5, class: "bg-gray-100 font-bold"}]
            rows << [
              {header: "Indicador", content: ""},
              {header: "Qtd de convites", content: ""},
              {header: "Convites", content: "Sem lançamentos"},
              {header: "Qtd de remarcações", content: ""},
              {header: "Remarcações", content: ""}
            ]
          end
        end
      
        rows
      end

      def fetch_reschedules_for_referral(referral_id, start_date, end_date)
        # Busca remarcações através das invitations do referral no período
        ClinicManagement::Appointment.joins(:invitation)
                                     .where(clinic_management_invitations: { referral_id: referral_id })
                                     .where(status: 'agendado')
                                     .where('clinic_management_appointments.created_at >= ? AND clinic_management_appointments.created_at <= ?', 
                                            start_date.beginning_of_day, end_date.end_of_day)
                                     .where(
                                       'EXISTS (SELECT 1 FROM clinic_management_appointments ca2 
                                        WHERE ca2.lead_id = clinic_management_appointments.lead_id 
                                        AND ca2.status = ? 
                                        AND ca2.created_at < clinic_management_appointments.created_at)',
                                       'remarcado'
                                     )
                                     .includes(:service, :lead, :invitation)
                                     .order(created_at: :desc)
      end

      def fetch_all_reschedules(start_date, end_date)
        # Busca todas as remarcações no período
        ClinicManagement::Appointment.joins(:invitation)
                                     .where(status: 'agendado')
                                     .where('clinic_management_appointments.created_at >= ? AND clinic_management_appointments.created_at <= ?', 
                                            start_date.beginning_of_day, end_date.end_of_day)
                                     .where(
                                       'EXISTS (SELECT 1 FROM clinic_management_appointments ca2 
                                        WHERE ca2.lead_id = clinic_management_appointments.lead_id 
                                        AND ca2.status = ? 
                                        AND ca2.created_at < clinic_management_appointments.created_at)',
                                       'remarcado'
                                     )
                                     .includes(:service, :lead, :invitation)
                                     .order(created_at: :desc)
      end

      def prepare_available_months_years(referral_id = nil)
        # Get date range from invitations (filtered by referral if provided)
        invitations_scope = referral_id.present? ? Invitation.where(referral_id: referral_id) : Invitation.all
        min_date = invitations_scope.minimum(:date) || Date.current
        max_date = Date.current
        
        available_dates = []
        current = min_date.beginning_of_month
        
        while current <= max_date
          available_dates << { month: current.month, year: current.year, label: I18n.l(current, format: '%B %Y') }
          current = current.next_month
        end
        
        available_dates.reverse
      end

      def prepare_invitations_reschedules_data(invitations, appointments, interactions)
        # Estrutura: { date => { referral => { invitations: [], reschedules: [], whatsapp_count: 0, phone_count: 0 } } }
        data = {}
        
        # Build map of User ID -> Referral
        user_referral_map = build_user_referral_map

        # Get all unique dates from invitations, appointments, and interactions
        invitation_dates = invitations.where.not(date: nil).map(&:date).compact
        appointment_dates = appointments.map { |apt| apt.created_at&.to_date }.compact
        interaction_dates = interactions.map { |i| i.occurred_at&.to_date }.compact
        
        all_dates = (invitation_dates + appointment_dates + interaction_dates).uniq.sort.reverse
        
        all_dates.each do |date|
          # Get data for this date
          date_invitations = invitations.select { |inv| inv.date == date }
          date_appointments = appointments.select { |apt| apt.created_at&.to_date == date }
          date_interactions = interactions.select { |i| i.occurred_at&.to_date == date }
          
          # Group by referral
          referral_data = {}
          
          # Process invitations
          date_invitations.group_by(&:referral).each do |referral, invites|
            referral_data[referral] ||= init_referral_data
            referral_data[referral][:invitations] = invites
          end
          
          # Process appointments (reschedules)
          date_appointments.group_by { |apt| apt.invitation&.referral }.each do |referral, apts|
            referral_data[referral] ||= init_referral_data
            referral_data[referral][:reschedules] = apts
          end

          # Process interactions
          date_interactions.group_by(&:user_id).each do |user_id, user_ints|
            referral = user_referral_map[user_id]
            next unless referral
            
            referral_data[referral] ||= init_referral_data
            
            # Count unique leads per interaction type (1 per lead/day limit)
            whatsapp_leads = user_ints.select { |i| i.interaction_type == 'whatsapp_click' }.map(&:lead_id).uniq
            phone_leads = user_ints.select { |i| i.interaction_type == 'phone_call' }.map(&:lead_id).uniq
            
            referral_data[referral][:whatsapp_count] += whatsapp_leads.count
            referral_data[referral][:phone_count] += phone_leads.count
          end
          
          data[date] = referral_data unless referral_data.empty?
        end
        
        data
      end

      def init_referral_data
        { invitations: [], reschedules: [], whatsapp_count: 0, phone_count: 0 }
      end

      def build_user_referral_map
        referrals_by_code = Referral.all.index_by(&:code)
        Membership.where(role: 'referral').where.not(code: nil).each_with_object({}) do |membership, map|
          if (referral = referrals_by_code[membership.code])
            map[membership.user_id] = referral
          end
        end
      end

      def get_referral_from_user(user_id)
        return nil if user_id.nil?
        
        user = User.find_by(id: user_id)
        return nil unless user
        
        # Find the referral membership for this user
        membership = user.memberships.find_by(role: 'referral')
        return nil unless membership&.code
        
        # Find the referral by code
        Referral.find_by(code: membership.code)
      end

      def appointment_link(appointment)
        return "" unless appointment&.invitation
        
        invitation = appointment.invitation
        count = appointment.lead.appointments.count
        
        render_to_string(
          partial: "patient_name_display",
          locals: { invitation: invitation, count: count }
        ).html_safe
      end

      def patient_link(invite, count = 1)
        render_to_string(
          partial: "patient_name_display",
          locals: { invitation: invite, count: count }
        ).html_safe
      end

      def current_path_with_params(new_params = {})
        # Merge current params with new params, preserving referral_id
        merged_params = params.permit(:referral_id).to_h.merge(new_params.stringify_keys)
        invitations_path(merged_params)
      end
      helper_method :current_path_with_params

      def last_appointment_link(last_appointment)
        if last_appointment&.service.present?
          helpers.link_to(invite_day(last_appointment), service_path(last_appointment.service), class: "text-blue-500 hover:text-blue-700", target: "_blank" )
        else
          ""
        end
      end

      def set_lead_name
        @services = Service.all    
        @regions = Region.all
        @invitation = Invitation.new
        @appointment = @invitation.appointments.build
        @lead = @invitation.build_lead
        @referrals = Referral.all
      end

      def responsible_content(invite)
        (invite.lead.name != invite.patient_name) ? invite.lead.name : ""
      end

      def generate_message_content(lead, appointment)
        render_to_string(
          partial: "clinic_management/lead_messages/lead_message_form",
          locals: { lead: lead, appointment: appointment }
        )
      end
      
      # Use callbacks to share common setup or constraints between actions.
      def set_invitation
        @invitation = Invitation.find(params[:id])
      end

      def next_services
        Service.where("date >= ?", Date.current).order(date: :asc)
      end

      # Only allow a list of trusted parameters through.
      def invitation_params
        params.require(:invitation).permit(
          :date,
          :notes,
          :region_id,
          :patient_name,
          :referral_id,
          :recapture_origin,
          :recapture_description,
          :recapture_description_extra,
          recapture_actions: [],
          recapture_screenshots: [],
          appointments_attributes: [
            :id,
            :service_id
          ],
          lead_attributes: [
            :name,
            :phone,
            :address,
            :latitude,
            :longitude
          ]
        )      
      end      

    def associate_with_existing_lead(params)
      phone = params.dig(:lead_attributes, :phone)
      # Sanitizar o telefone para busca (remover caracteres da máscara)
      clean_phone = phone.gsub(/\D/, '')
      existing_lead = ClinicManagement::Lead.find_by(phone: clean_phone)
      
      if existing_lead.present?
        # Atualizar informações se necessário
        merge_lead_information(existing_lead, params, params[:patient_name], params.dig(:lead_attributes, :name))
        existing_lead
      else
        # Sanitizar os parâmetros do lead antes de criar
        lead_params = params[:lead_attributes].dup
        lead_params[:phone] = clean_phone if lead_params[:phone].present?
        Lead.create!(lead_params)
      end
    end

    def transfer_phone_to_new_lead(params)
      phone = params.dig(:lead_attributes, :phone)
      # Sanitizar o telefone para busca (remover caracteres da máscara)
      clean_phone = phone.gsub(/\D/, '')
      old_lead = ClinicManagement::Lead.find_by(phone: clean_phone)
      
      if old_lead.present?
        # Sanitizar os parâmetros do lead antes de criar
        lead_params = params[:lead_attributes].dup
        lead_params[:phone] = clean_phone if lead_params[:phone].present?
        
        # Criar novo lead
        new_lead = Lead.create!(lead_params)
        
        # Limpar telefone do lead antigo
        old_lead.update!(phone: nil)
        
        Rails.logger.info "Telefone #{phone} transferido do lead #{old_lead.id} para o lead #{new_lead.id}"
        
        new_lead
      else
        # Sanitizar os parâmetros do lead antes de criar
        lead_params = params[:lead_attributes].dup
        lead_params[:phone] = clean_phone if lead_params[:phone].present?
        Lead.create!(lead_params)
      end
    end

    def calculate_conversion_class(rate)
      if rate >= 40
        'excellent'
      elsif rate >= 30
        'good'
      elsif rate >= 20
        'average'
      else
        'low'
      end
    end
  end
end
