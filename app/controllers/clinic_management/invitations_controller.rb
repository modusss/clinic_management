module ClinicManagement
  class InvitationsController < ApplicationController
    before_action :set_invitation, only: %i[ show edit update destroy ]

    # GET /invitations
    def index
      @invitations = Invitation.all
    end

    # GET /invitations/1
    def show
    end

    # GET /invitations/new
    def new
      # @invitation = Invitation.new
      @services = Service.all    
      @invitation = Invitation.new
      @appointment = @invitation.build_appointment
      @regions = Region.all
    end

    # GET /invitations/1/edit
    def edit
    end

    # POST /invitations
    def create
      @invitation = Invitation.new(invitation_params)

      if @invitation.save
        redirect_to @invitation, notice: "Invitation was successfully created."
      else
        render :new, status: :unprocessable_entity
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
      # Use callbacks to share common setup or constraints between actions.
      def set_invitation
        @invitation = Invitation.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def invitation_params
        params.require(:invitation).permit(:patient_name, :notes, :lead_id, :referral_id, :region_id, :appointment_id)
      end
      def invitation_params
        params.require(:invitation).permit(:patient_name, :notes, :referral_id, :region_id, :appointment_id, lead_attributes: [:id, :name, :email])
      end
      
  end
end
