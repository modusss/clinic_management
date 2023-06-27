module ClinicManagement
  class PrescriptionsController < ApplicationController
    before_action :set_appointment, except: [:today_list]
    
    def index

    end

    def today_list
      @service = Service.find_by(date: Date.today)
      if @service.present?
        @appointments = @service.appointments
        @rows = @appointments.map.with_index(1) do |ap, index|
          invitation = ap.invitation
          [
            {header: "#", content: index },
            {header: "Paciente", content: invitation.patient_name},
            {header: "Comparecimento", content: ap.attendance == true ? "sim" :  "--"}
          ]
        end
      end
    end

    def show
      @prescription = @appointment.prescription
    end

    def new
      @prescription = @appointment.build_prescription
      @service = @appointment.service
      @patients = @service.appointments.joins(:invitation).pluck('clinic_management_invitations.patient_name')
    end

    def create
      @prescription = @appointment.build_prescription(prescription_params)
      if @prescription.save
        redirect_to lead_path(@appointment.lead), notice: 'Prescription was successfully created.'
      else
        render :new
      end
    end

    def edit
      @prescription = @appointment.prescription
    end

    def update
      @prescription = @appointment.prescription
      if @prescription.update(prescription_params)
        redirect_to appointment_prescription_path(@appointment), notice: 'Prescription was successfully updated.'
      else
        render :edit
      end
    end

    def destroy
      @prescription = @appointment.prescription
      @prescription.destroy
      redirect_to @appointment, notice: 'Prescription was successfully destroyed.'
    end

    private

    def set_appointment
      @appointment = Appointment.find(params[:appointment_id])
    end

    def prescription_params
      params.require(:prescription).permit(:sphere_right, :sphere_left, :cylinder_right, :cylinder_left, :axis_right, :axis_left, :add_right, :add_left, :comment)
    end
  end
end
