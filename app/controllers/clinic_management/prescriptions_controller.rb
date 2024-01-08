module ClinicManagement
  class PrescriptionsController < ApplicationController
    before_action :set_appointment, except: [:index_today, :generate_order_pdf]
    skip_before_action :redirect_doctor_users, only: [:index_today, :show_today, :new_today, :edit_today, :update, :create]
    include GeneralHelper

    def index

    end

    def index_today
      @service = Service.find_by(date: Date.today)
      if @service.present?
        @appointments = @service.appointments.sort_by { |ap| ap&.invitation&.patient_name }  
        @rows = @appointments.map.with_index(1) do |ap, index|
          invitation = ap.invitation
          lead = invitation.lead
          if helpers.doctor?(current_user)
            [
              {header: "#", content: index },
              {header: "Paciente", content: invitation.patient_name},
              {header: "Comparecimento", content: ap.attendance == true ? "sim" :  "--"},
              {header: "Receita", content: prescription_link(ap)}
            ]
          else
            [
              {header: "#", content: index },
              {header: "Paciente", content: helpers.link_to(invitation.patient_name, lead_path(lead), class: "text-blue-500 hover:text-blue-700", target: "_blank" )},
              {header: "Telefone", content: helpers.link_to(lead.phone, "https://wa.me/+55#{lead.phone}", class: "text-blue-500 hover:text-blue-700")},
              {header: "Tornar cliente", content: set_conversion_link(lead), class: "text-purple-500" },
              {header: "Mensagem", content: generate_message_content(lead, ap), id: "whatsapp-link-#{lead.id.to_s}" },
              {header: "Mensagens enviadas:", content: ap&.messages_sent&.join(', '), id: "messages-sent-#{ap.id.to_s}" },            
              {header: "Comparecimento", content: ap.attendance == true ? "sim" :  "--"},
              {header: "Receita", content: prescription_link(ap)}
            ]
          end
        end
      end
    end

    def show_today
      @prescription = @appointment.prescription
    end

    def show
      @prescription = @appointment.prescription
    end

    def generate_order_pdf
      @order_number = params[:order_number]
      respond_to do |format|
        format.html
        format.pdf do
          render pdf: "ordem_#{@order_number}",
                 template: "clinic_management/prescriptions/order_pdf",
                 formats: [:html],
                 encoding: "UTF-8",
                 page_height: '80',
                 page_width: '80',
                 margin: { top: '5mm', bottom: '5mm', left: '5mm', right: '5mm' },
                 dpi: '300'
        end
      end
    end
    

    def pdf
      @prescription = @appointment.prescription
      
      respond_to do |format|
        format.html
        format.pdf do
            render pdf: "receita", 
            template: "clinic_management/prescriptions/pdf", 
            formats: [:html],
            encoding: "UTF-8",
            page_size: "A4",
            margin: { top: 10, bottom: 10, left: 10, right: 10 },
            dpi: 300,
            zoom: 1,
            orientation: "Portrait"
        end
      end  
      # render pdf: "pdf",   # Nome do arquivo PDF
      #        template: "clinic_management/prescriptions/pdf.html.erb"  # Caminho para a view
    end

    def new
      new_settings
    end

    def new_today
      new_settings
    end

    def create
      @prescription = @appointment.build_prescription(prescription_params)
      @prescription.doctor_name = current_user.name if helpers.doctor?(current_user)
      if @prescription.save
        @appointment.attendance = true
        @appointment.save
        if request.referrer.include?("new_today")
          redirect_to index_today_path, notice: 'Prescription was successfully updated.'
        else
          redirect_to lead_path(@appointment.lead), notice: 'Prescription was successfully created.'
        end
      else
        render :new
      end
    end

    def edit
      @prescription = @appointment.prescription
    end

    def edit_today
      @prescription = @appointment.prescription
    end

    def update
      @prescription = @appointment.prescription
      @prescription.doctor_name = current_user.name if helpers.doctor?(current_user)
      if @prescription.update(prescription_params)
        if request.referrer.include?("edit_today")
          redirect_to show_today_appointment_prescription_path(@appointment, @prescription), notice: 'Prescription was successfully updated.'
        else
          redirect_to appointment_prescription_path(@appointment), notice: 'Prescription was successfully updated.'
        end
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

    def generate_message_content(lead, appointment)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: lead, appointment: appointment }
      )
    end

    def set_conversion_link(lead)
      if lead.leads_conversion.present?
        helpers.link_to("Página do cliente", main_app.customer_orders_path(lead.customer), class: "text-blue-500 hover:text-blue-800 underline")
      else
        helpers.link_to("Converter para cliente", main_app.new_conversion_path(lead_id: lead.id), class: "text-red-500 hover:text-red-800 underline")
      end
   end

    def new_settings
      @prescription = @appointment.build_prescription
      @service = @appointment.service
      @patients = @service.appointments.joins(:invitation).pluck('clinic_management_invitations.patient_name')
    end

    def prescription_link(ap)
      if ap.prescription.present?
        helpers.link_to("Ver receita", show_today_appointment_prescription_path(ap, ap.prescription), class: "text-white bg-indigo-500 hover:bg-indigo-600 px-4 py-2 rounded")
      else
        helpers.link_to("Lançar receita", new_today_appointment_prescriptions_path(ap), class: "bg-blue-600 hover:bg-blue-800 text-white py-2 px-4 rounded")
      end
    end

    def set_appointment
      @appointment = Appointment.find(params[:appointment_id])
    end

    def prescription_params
      params.require(:prescription).permit(:sphere_right, :sphere_left, :cylinder_right, :cylinder_left, :axis_right, :axis_left, :add_right, :add_left, :comment)
    end
  end
end
