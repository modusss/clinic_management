module ClinicManagement
  class InvitationsController < ApplicationController
    before_action :set_invitation, only: %i[ show edit update destroy ]
    skip_before_action :redirect_referral_users, only: [:new, :create, :update]
    include GeneralHelper

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
      @services = Service.where("date >= ?", Date.today)
      @regions = Region.all.order(:name)
      @invitation = Invitation.new
      @appointment = @invitation.appointments.build
      @lead = @invitation.build_lead
      @referrals = Referral.all    
      begin
        @today_invitations = helpers.user_referral.invitations.where('created_at >= ?', Date.today.beginning_of_day).limit(100)
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
        redirect_to @appointment.service
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
      redirect_to invitations_url, notice: "Invitation was successfully destroyed."
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
        date: @invitation.date
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
        invitations.map do |invite|
          last_appointment = invite.lead.appointments.last
          lead = invite.lead
          [
            {header: "Data", content: invite&.date&.strftime("%d/%m/%Y")},
            {header: "Para", content: last_appointment_link(last_appointment)},
            {header: "Paciente", content: helpers.link_to(invite.patient_name, lead_path(lead), class: "text-blue-500 hover:text-blue-700", target: "_blank")},
            {header: "Responsável", content: responsible_content(invite)},   
            {header: "Telefone", content: lead.phone},
            {header: "Observação", content: invite.notes},
            {header: "Mensagem", content: generate_message_content(lead, last_appointment), id: "whatsapp-link-#{lead.id}" },
            {header: "Mensagens enviadas:", content: last_appointment.messages_sent.join(', ') },
            {header: "Indicação", content: invite.referral.name},
            {header: "Quantidade de convites", content: lead.appointments.count},
            {header: "Região", content: invite.region.name}
          ]
        end
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
