module ClinicManagement
  class AppointmentsController < ApplicationController
    before_action :set_appointment, only: %i[ show edit update destroy ]

    # GET /appointments
    def index
    end

    def index_by_referral
      @referral = Referral.find(params[:referral_id])
      @appointments = @referral.invitations.includes(:appointments).map(&:appointments).flatten
    end    

    # GET /appointments/1
    def show
    end

    # GET /appointments/new
    def new
      @appointment = Appointment.new
    end

    # GET /appointments/1/edit
    def edit
    end

    # POST /appointments
    def create
      @appointment = Appointment.new(appointment_params)
      if @appointment.save
        @appointment.lead.update(last_appointment_id: @appointment.id)
        redirect_to @appointment, notice: "Appointment was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def reschedule
      before_appointment = Appointment.find_by(id: params[:id])
      @lead = before_appointment.lead
      @next_service = Service.find_by(id: params[:appointment][:service_id])
      if before_appointment&.present? && @lead&.present? && @next_service&.present?
        @appointment = @lead.appointments.build(
          invitation: before_appointment.invitation,
          service: @next_service,
          status: "agendado"
        )
        if @appointment.save
          before_appointment.update(status: "remarcado")
          @lead.update(last_appointment_id: @appointment.id)
          redirect_to @next_service, notice: "Appointment was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end
    
    # PATCH/PUT /appointments/1
    def update
      if @appointment.update(appointment_params)
        @appointment.lead.update(last_appointment_id: @appointment.id)
        redirect_to @appointment, notice: "Appointment was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /appointments/1
    def destroy
      @appointment.destroy
      redirect_to appointments_url, notice: "Appointment was successfully destroyed."
    end

    def set_attendance
      @appointment = Appointment.find(params[:id])
      button_id = "set-attendance-button-#{@appointment.id}"
      @appointment.attendance = true
      @appointment.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [ 
                                turbo_stream.update(button_id, "--"),
                                turbo_stream.replace("attendance-#{@appointment.id}", partial: 'clinic_management/appointments/attendance_table_status', locals: { appointment: @appointment })
                                ]
        end
      end      
    end

    def cancel_attendance
      @appointment = Appointment.find(params[:id])
      button_id = "cancel-attendance-button-#{@appointment.id}"
      status_id = "status-#{@appointment.id}"
      @appointment.status = "cancelado"
      @appointment.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [ 
                                turbo_stream.update(button_id, "--"),
                                turbo_stream.replace(status_id, partial: 'clinic_management/appointments/status_table', locals: { status: @appointment.status })
                               ]
        end
      end
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_appointment
        @appointment = Appointment.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def appointment_params
        params.require(:appointment).permit(:attendance, :status, :lead_id, :service_id)
      end
  end
end
