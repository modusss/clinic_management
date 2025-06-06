module ClinicManagement
  class AppointmentsController < ApplicationController
    before_action :set_appointment, only: %i[ show edit update destroy ]
    skip_before_action :redirect_referral_users, only: [:reschedule, :create, :update, :update_comments]

    # POST /appointments
    def create
      params = request.params[:appointment]
      @lead = Lead.find_by(id: params[:lead_id])
      @service = Service.find_by(id: params[:service_id])
      @invitation = Invitation.new(
        referral_id: Referral.find_by(name: "Local").id,
        region_id: Region.find_by(name: "Local").id,
        patient_name: @lead.name,
        lead_id: @lead.id
      )
      if @invitation.save
        @appointment = @lead.appointments.build(
          invitation: @invitation,
          service: @service,
          referral_code: @invitation&.referral&.code,
          status: "agendado"
        )
        if @appointment.save
          redirect_to @service
        end
      end
    end

    def reschedule
      before_appointment = Appointment.find_by(id: params[:id])
      @lead = before_appointment.lead
      # Simplificar a lógica de encontrar o referral
      # verify if current user is referral user 
      if helpers.referral?(current_user)
        referral = helpers.user_referral
      else
        referral = if params[:referral_id].present?
          Referral.find_by(id: params[:referral_id])
        else
          if before_appointment.created_at < 12.month.ago
            Referral.find_by(name: "Local")
          else
            before_appointment.invitation.referral
          end
        end
      end

      invitation = Invitation.create(
        referral_id: referral.id,
        region_id: reschedule_region(referral, @lead).id,
        patient_name: before_appointment.invitation.patient_name,
        lead_id: @lead.id
      )

      service_id = params.dig(:appointment, :service_id) || params[:service_id]
      @next_service = Service.find_by(id: service_id)
      if before_appointment&.present? && @lead&.present? && @next_service&.present?
        @appointment = @lead.appointments.build(
          invitation: invitation,
          service: @next_service,
          status: "agendado",
          referral_code: invitation&.referral&.code
        )
        if @appointment.save
          before_appointment.update(status: "remarcado")
          @lead.update(last_appointment_id: @appointment.id)
          if helpers.referral? current_user
            # redirect_to request.original_url
            redirect_to show_by_referral_services_path(referral_id: @appointment.invitation.referral.id, id: @next_service.id)
          else
            redirect_to @next_service
          end
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

    def update_comments
      @appointment = ClinicManagement::Appointment.find(params[:id])
      if @appointment.update(appointment_params)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "appointment-comments-#{@appointment.id}",
              partial: "clinic_management/shared/appointment_comments",
              locals: { appointment: @appointment, message: "Atualizado!" }
            )
          end
        end
      else
        head :unprocessable_entity
      end
    end

    def toggle_confirmation
      @appointment = Appointment.find(params[:id])
      @appointment.update(confirmed: !@appointment.confirmed)
      # redirect_back(fallback_location: service_path(@appointment.service))
    end

    private

      def reschedule_region(referral, lead)
        if referral.name.downcase == "local"
          Region.find_by(name: "Local")
        else
          lead.invitations.last.region
        end
      end
    
      # Use callbacks to share common setup or constraints between actions.
      def set_appointment
        @appointment = Appointment.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def appointment_params
        params.require(:appointment).permit(:attendance, :status, :lead_id, :service_id, :comments, :confirmed)
      end
  end
end
