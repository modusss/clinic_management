module ClinicManagement
  class LeadsController < ApplicationController
    before_action :set_lead, only: %i[ show edit update destroy ]

    # GET /leads
    def index
      @leads = Lead.all
    end

    # GET /leads/1
    def show
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
      @lead = Lead.new(lead_params)

      if @lead.save
        redirect_to @lead, notice: "Lead was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /leads/1
    def update
      if @lead.update(lead_params)
        redirect_to @lead, notice: "Lead was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /leads/1
    def destroy
      @lead.destroy
      redirect_to leads_url, notice: "Lead was successfully destroyed."
    end

    def absent
      @leads = Lead.joins(appointments: [:invitation, :service])
                   .where(clinic_management_appointments: { id: :last_appointment_id, attendance: false })
                   .where('clinic_management_services.date < ?', Date.today)
                   .order('clinic_management_invitations.created_at DESC')
                   .distinct
      render :index
    end
    
    def attended
      @leads = Lead.joins(appointments: [:invitation, :service])
                   .where(clinic_management_appointments: { id: :last_appointment_id, attendance: true })
                   .where('clinic_management_services.date < ?', Date.today)
                   .order('clinic_management_invitations.created_at DESC')
                   .distinct
      render :index
    end
    
    def cancelled
      @leads = Lead.joins(appointments: [:invitation, :service])
                   .where(clinic_management_appointments: { id: :last_appointment_id, status: 'cancelado' })
                   .where('clinic_management_services.date < ?', Date.today)
                   .order('clinic_management_invitations.created_at DESC')
                   .distinct
      render :index
    end
    

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_lead
        @lead = Lead.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def lead_params
        params.require(:lead).permit(:name, :phone, :address, :converted)
      end
  end
end
