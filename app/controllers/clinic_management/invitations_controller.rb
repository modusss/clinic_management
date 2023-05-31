module ClinicManagement
  class InvitationsController < ApplicationController
    before_action :set_invitation, only: %i[ show edit update destroy ]
    include GeneralHelper

    # GET /invitations
    def index
      if Invitation.all.present?
        @rows = process_invitations_data(Invitation.all.includes(:lead, :region, appointments: :service).order(date: :desc))
      else
        @rows = ""
      end
    end

    # GET /invitations/1
    def show
    end

    # GET /invitations/new
    def new
      @services = Service.all    
      @regions = Region.all
      @invitation = Invitation.new
      @appointment = @invitation.appointments.build
      @lead = @invitation.build_lead
      @referrals = Referral.all    
    end

    # GET /invitations/1/edit
    def edit
    end

    def create
      begin
        ActiveRecord::Base.transaction do
          @lead = Lead.create!(invitation_params[:lead_attributes])
          @invitation = Invitation.new(invitation_params.except(:lead_attributes, :appointments_attributes))
          @invitation.lead = @lead
          @invitation.save!
          @lead.name = @invitation.patient_name if @lead.name.blank?
          @lead.save               
          @appointment = @invitation.appointments.build(invitation_params[:appointments_attributes]["0"])
          @appointment.status = "agendado"
          @appointment.lead = @lead
          @appointment.save!
        end
        invitation_list_locals = {invitation: @invitation, appointment: @appointment}
        # attributes that is going to be kept as slected fields when reloads form for next invitation
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

        # redirect_to new_invitation_path, notice: 'Convite de ' + @lead.name + ' criado com sucesso!'
      rescue ActiveRecord::RecordInvalid => exception
        validation_content = exception.record.errors.full_messages.join(', ')
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update("validation", validation_content)
          end
        end
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
          [
            {header: "Data", content: invite&.date&.strftime("%d/%m/%Y")},
            {header: "Para", content: helpers.link_to(invite_day(last_appointment), service_path(last_appointment.service), class: "text-blue-500 hover:text-blue-700", target: "_blank" )},
            {header: "Paciente", content: helpers.link_to(invite.patient_name, lead_path(invite.lead), class: "text-blue-500 hover:text-blue-700", target: "_blank")},
            {header: "Responsável", content: responsible_content(invite)},   
            {header: "Telefone", content: invite.lead.phone},
            {header: "Observação", content: invite.notes},
            {header: "Indicação", content: invite.referral.name},
            {header: "Quantidade de convites", content: invite.lead.appointments.count},
            {header: "Região", content: invite.region.name}
          ]
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
