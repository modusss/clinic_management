module ClinicManagement
  class InvitationsController < ApplicationController
    before_action :set_invitation, only: %i[ show edit update destroy ]
    skip_before_action :redirect_referral_users, only: [:new, :create, :update]
    include GeneralHelper

    # GET /invitations
    def index
      @invitations = Invitation.all.includes(:lead, :region, appointments: :service).order(created_at: :desc).page(params[:page]).per(30)
      if @invitations.present?
        @rows = process_invitations_data(@invitations)
      else
        @rows = ""
      end
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
        @today_invitations = helpers.user_referral.invitations.where('created_at >= ?', Date.today.beginning_of_day).limit(100)
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
          @lead = check_existing_leads(invitation_params)
          @invitation = @lead.invitations.build(invitation_params.except(:lead_attributes, :appointments_attributes))
          @lead.update!(name: @invitation.patient_name) if @lead.name.blank?
          appointment_params = invitation_params[:appointments_attributes]["0"].merge({status: "agendado", lead: @lead})
          existing_appointment = @lead.appointments.find_by(service_id: appointment_params[:service_id])    
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
          @lead = check_existing_leads(invitation_params)
          @invitation = @lead.invitations.new(invitation_params.except(:lead_attributes, :appointments_attributes))       
          @invitation.region = set_local_region
          @invitation.save!
          @lead.update!(name: @invitation.patient_name) if @lead.name.blank?    
          appointment_params = invitation_params[:appointments_attributes]["0"].merge({status: "agendado", lead: @lead})
          existing_appointment = @lead.appointments.find_by(service_id: appointment_params[:service_id])
          if existing_appointment
            @lead.errors.add(:base, "Este paciente chamado #{@lead.name} já está agendado para este atendimento.")
            raise ActiveRecord::RecordInvalid.new(@lead)
          else
            @appointment = @invitation.appointments.build(appointment_params)
            @appointment.referral_code = @invitation&.referral&.code
            @appointment.save!
          end
        end
        if @appointment.service.date == Date.today
          redirect_to index_today_path
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

    private

    def check_existing_leads(params)
      first_name = params.dig(:lead_attributes, :name)&.split&.first || invitation_params[:patient_name]&.split&.first   
      phone = params.dig(:lead_attributes, :phone)
      lead = Lead.find_by_phone(phone)
      return Lead.create!(params[:lead_attributes]) unless lead   
      lead.name.match?(/#{Regexp.escape(first_name)}/i) ? lead : Lead.create!(params[:lead_attributes])
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
        invitations.group_by { |invite| [invite.date, invite.referral] }.map do |(date, referral), invites|
          [
            {header: "Data", content: date&.strftime("%d/%m/%Y")},
            {header: "Indicador" , content: referral&.name},
            {header: "Qtd de convites", content: invites.size},
            {header: "Lista de convidados" , content: invites.map { |invite| patient_link(invite) }.join(", ").html_safe},
            {header: "Regiões" , content: invites.map { |invite| invite&.region&.name }.uniq.join(", ")}
          ]
        end
      end
      
      def patient_link(invite)
        helpers.link_to(invite.patient_name.split(" ").first, lead_path(invite.lead), class: "text-blue-500 hover:text-blue-700", target: "_blank")
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
        Service.where("date >= ?", Date.today).order(date: :asc)
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
            :address
          ]
        )      
      end      
  end
end
