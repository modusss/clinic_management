module ClinicManagement
  class InvitationsController < ApplicationController
    before_action :set_invitation, only: %i[ show edit update destroy ]
    skip_before_action :redirect_referral_users, only: [:new, :create, :update, :index, :edit_patient_name, :update_patient_name, :check_existing_phone]
    include GeneralHelper

    # GET /invitations
    def index
      @referrals = Referral.all
      if params[:referral_id].present?
        @invitations = Invitation.where(referral_id: params[:referral_id]).includes(:lead, :region, appointments: :service).order(created_at: :desc).page(params[:page]).per(800)
      else
        @invitations = Invitation.all.includes(:lead, :region, appointments: :service).order(created_at: :desc).page(params[:page]).per(800)
      end
      if @invitations.present?
        @rows = process_invitations_data(@invitations)
      else
        @rows = ""
      end
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
          
          appointment_params = invitation_params[:appointments_attributes]["0"].merge({status: "agendado", lead: @lead})
          existing_appointment = already_schedule_this_patient?(@invitation, appointment_params[:service_id])   
          
          if existing_appointment
            @lead.errors.add(:base, "Este paciente chamado #{@lead.name} já está agendado para este atendimento.")
            @invitation.destroy
            raise ActiveRecord::RecordInvalid.new(@lead)
          else
            @appointment = @invitation.appointments.build(appointment_params)
            @appointment.referral_code = @invitation&.referral&.code
            @appointment.save!
          end
        end
        @lead.update(last_appointment_id: @appointment.id)
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
          
          @invitation = @lead.invitations.new(invitation_params.except(:lead_attributes, :appointments_attributes))       
          @invitation.region = set_local_region
          @invitation.save!
          @lead.update!(name: @invitation.patient_name) if @lead.name.blank?    
          
          appointment_params = invitation_params[:appointments_attributes]["0"].merge({status: "agendado", lead: @lead})
          existing_appointment = already_schedule_this_patient?(@invitation, appointment_params[:service_id])
          
          if existing_appointment
            @lead.errors.add(:base, "Este paciente chamado #{@lead.name} já está agendado para este atendimento.")
            raise ActiveRecord::RecordInvalid.new(@lead)
          else
            @appointment = @invitation.appointments.build(appointment_params)
            @appointment.referral_code = @invitation&.referral&.code
            @appointment.save!
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
        existing_lead = ClinicManagement::Lead.find_by(phone: phone)
        
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
    
          delivered_orders = referral.commissions.where(created_at: month_start..month_end)
                                                  .joins(:order)
                                                  .where(orders: { delivery_status: 'DELIVERED' })
                                                  .count
    
          {
            referral: referral.name,
            days_worked: invitations.map(&:date).uniq.size,
            invited: invitations.size,
            conversions: converted_leads,
            conversion_rate: converted_leads.to_f / invitations.size * 100,
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
      
      existing_lead = Lead.find_by(phone: phone)
      
      if existing_lead.present?
        Rails.logger.info "Usando lead existente (ID: #{existing_lead.id}) para telefone: #{phone}"
        
        # Auto-merge de informações
        merge_lead_information(existing_lead, params, patient_name, lead_name)
        
        # Log da ação para auditoria
        Rails.logger.info "Lead #{existing_lead.id} atualizado com novas informações do convite"
        
        return existing_lead
      else
        Lead.create!(params[:lead_attributes])
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

      def patient_link(invite, count = 1)
        render_to_string(
          partial: "patient_name_display",
          locals: { invitation: invite, count: count }
        ).html_safe
      end

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
      existing_lead = ClinicManagement::Lead.find_by(phone: phone)
      
      if existing_lead.present?
        # Atualizar informações se necessário
        merge_lead_information(existing_lead, params, params[:patient_name], params.dig(:lead_attributes, :name))
        existing_lead
      else
        Lead.create!(params[:lead_attributes])
      end
    end

    def transfer_phone_to_new_lead(params)
      phone = params.dig(:lead_attributes, :phone)
      old_lead = ClinicManagement::Lead.find_by(phone: phone)
      
      if old_lead.present?
        # Criar novo lead
        new_lead = Lead.create!(params[:lead_attributes])
        
        # Limpar telefone do lead antigo
        old_lead.update!(phone: nil)
        
        Rails.logger.info "Telefone #{phone} transferido do lead #{old_lead.id} para o lead #{new_lead.id}"
        
        new_lead
      else
        Lead.create!(params[:lead_attributes])
      end
    end
  end
end
