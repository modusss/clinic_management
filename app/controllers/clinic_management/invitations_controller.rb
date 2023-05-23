module ClinicManagement
  class InvitationsController < ApplicationController
    before_action :set_invitation, only: %i[ show edit update destroy ]
    include GeneralHelper

    # GET /invitations
    def index
      @rows = process_invitations_data(Invitation.all.includes(:lead, :region, appointment: :service).order(date: :desc))
    end

    # GET /invitations/1
    def show
    end

    # GET /invitations/new
    def new
      # @invitation = Invitation.new
      @services = Service.all    
      @regions = Region.all
      @invitation = Invitation.new
      @appointment = @invitation.build_appointment
      @lead = @invitation.build_lead
    end

    # GET /invitations/1/edit
    def edit
    end

    # POST /invitations
    def create
      @invitation = build_invitation_with_associations
      result = save_all_and_report_errors(@invitation.appointment, @invitation)
      if result[:status] == :error
        @invitation.lead.destroy
        result[:errors].each do |model, error_messages|
          puts "Errors for #{model.class.name}:"
          error_messages.each { |message| puts "- #{message}" }
        end
      else
        associate_appointment_with_lead
        redirect_to @invitation, notice: "Invitation was successfully created."
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

      def process_invitations_data(invitations)
        invitations.map do |invite|
          last_appointment = invite.lead.appointments.last
          [
            {header: "Data", content: invite.date.strftime("%d/%m/%Y")},
            {header: "Para", content: helpers.link_to(invite_day(invite), service_path(invite.appointment.service), class: "text-blue-500 hover:text-blue-700", target: "_blank" )},
            {header: "Paciente", content: invite.patient_name},
            {header: "Responsável", content: responsible_content(invite)},   
            {header: "Telefone", content: invite.lead.phone},
            {header: "Observação", content: invite.notes},
            {header: "Indicação", content: invite.referral.name},
            {header: "Quantidade de convites", content: invite.lead.appointments.count},
            {header: "Região", content: invite.region.name}
          ]
        end
      end

      def responsible_content(invite)
        (invite.lead.name != invite.patient_name) ? invite.lead.name : ""
      end

      def associate_appointment_with_lead
        appointment = @invitation.appointment
        appointment.lead = @invitation.lead
        appointment.save
      end

      def build_invitation_with_associations
        Invitation.new(invitation_params).tap do |invitation|
          invitation.lead = set_lead(invitation)
          if invitation.lead.save # Save the Lead first
            invitation.appointment = set_appointment(invitation, invitation.lead)
            invitation.referral = Referral.first
          end
        end
      end

      def save_all_and_report_errors(*models)
        errors = {}
        all_saved = models.all? do |model|
          if model.save
            true
          else
            errors[model] = model.errors.full_messages
            false
          end
        end
        all_saved ? { status: :success } : { status: :error, errors: errors }
      end
      

      def set_lead(invitation)
        params = invitation_params[:lead_attributes]
        invitation.build_lead(
          name: params[:name].blank? ? invitation.patient_name : params[:name],
          phone: params[:phone],
          address: params[:address]
        )
      end
      
      def set_appointment(invitation, lead)
        invitation.build_appointment.tap do |appointment|
          appointment.service_id = invitation_params[:appointment_attributes][:service_id]
          appointment.status = "agendado"
          appointment.lead = lead
        end
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
          appointment_attributes: [
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
