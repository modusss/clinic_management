  module ClinicManagement
    class PrescriptionsController < ApplicationController
      before_action :set_appointment, except: [:index_today, :generate_order_pdf, :search_index_today, :index_next, :index_before]
      skip_before_action :redirect_doctor_users, only: [:index_today, :show_today, :new_today, :edit_today, :update, :create, :search_index_today]
      skip_before_action :authenticate_user!, only: [:pdf]
      before_action :set_view_type, only: [:index_today, :index_next, :index_before]
      include GeneralHelper, PrescriptionsHelper

      def index

      end

      def index_today
        @services = Service.where(date: Date.current).order(:start_time)
        @rows = mapping_rows(@services)
      end

          # GET /prescriptions/index_next
      # Shows all services scheduled for the next available day after today (not including today)
      def index_next
        next_date = Service.where('date > ?', Date.current).order(:date).pluck(:date).first
        @services = Service.where(date: next_date).order(:start_time)
        @rows = mapping_rows(@services)
      end

      def index_before
        # Busca o dia anterior ao dia atual que tenha pelo menos um service
        before_date = Service.where('date < ?', Date.current).order(date: :desc).pluck(:date).first
        @services = Service.where(date: before_date).order(:start_time)
        @rows = mapping_rows(@services)
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
        @company_contact = current_account&.account_contact_info
        
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
      end

      def search_index_today
        if params[:q].present?
          # get all appointments from the services which has date = Date.current
          appointments = Appointment.where(service_id: Service.where(date: Date.current).pluck(:id))
          # find the appointments with the given patient_name on params[:q]
          @appointments = appointments.select { |appointment| appointment.invitation.patient_name.downcase.include?(params[:q].downcase) }
          # display via turbo_stream a tabel of results on div id #appointment-results
            @rows = process_appointments_data(@appointments)
        else
            @rows = "" 
        end
        respond_to do |format|
          prescription = @appointments&.first&.prescription
          if @rows.size == 1 && prescription.present?
            content = render_to_string(partial: "clinic_management/prescriptions/search_patient_info", locals: { prescription: prescription })
          else
            content = ""
          end
          format.turbo_stream do
              render turbo_stream: [
                    turbo_stream.update("appointments-results", helpers.data_table(@rows, 3)),
                    turbo_stream.update("appointment-info", content)
              ]
          end
        end   
      end

      def new
        new_settings
      end

      def new_today
        new_settings
        @lead = @appointment.lead
        # Busca todas as receitas anteriores do lead, ordenadas da mais recente para a mais antiga
        @previous_prescriptions = ClinicManagement::Prescription
          .joins(:appointment)
          .where(clinic_management_appointments: { lead_id: @lead.id })
          .order(created_at: :desc)
        # Buscar exames anteriores (appointments), exceto o atual
        @previous_appointments = @lead.appointments
          .where.not(id: @appointment.id)
          .includes(:service, :invitation)
          .order('clinic_management_services.date DESC')
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

      def send_whatsapp
        @prescription = @appointment.prescription
        pdf_url = pdf_appointment_prescription_url(@appointment, format: :pdf, host: Rails.application.config.action_mailer.default_url_options[:host])
        phone = @appointment.lead.phone
        response = helpers.send_api_zap_pdf(pdf_url, "Dados do teste de vista optométrico", phone, false)

        respond_to do |format|
          format.js do
            if response.success?
              flash.now[:notice] = "Receita enviada com sucesso!"
            else
              flash.now[:alert] = "Falha ao enviar a receita."
            end
          end
        end

        # redirect_to appointment_prescription_path(@appointment)
      end

      private

      def set_view_type
        @view_type = mobile_device? ? 'cards' : (params[:view_type] || cookies[:preferred_prescriptions_today_view] || 'table')
      end

      def mapping_rows(services)
        services.map do |service|
          # Filtra as appointments para remover aquelas onde appointment.invitation é nil
          appointments = service.appointments
                                .select { |ap| ap.invitation.present? }
                                .sort_by { |ap| ap.invitation.patient_name }
          process_appointments_data(appointments)
        end
      end
      
      

      def process_appointments_data(appointments)
        appointments.map.with_index(1) do |ap, index|
          invitation = ap&.invitation
          lead = invitation&.lead
          next unless (invitation.present?) && (lead.present?) && (ap.present?) && (lead.name.present?) 
    
          if helpers.doctor?(current_user)
            next unless ap.attendance == true
            [
              {header: "#", content: index},
              {header: "Paciente", content: invitation.patient_name, class: "size_20 nowrap patient-name"},
              {header: "Comparecimento", content: ap.attendance == true ? "sim" : "--"},
              {header: "Receita", content: prescription_link(ap), class: "nowrap"}
            ]
          else
            [
              {header: "#", content: index},
              {
                header: "Paciente", 
                content: render_to_string(
                  partial: "clinic_management/leads/patient_name_with_edit_button", 
                  locals: { invitation: ap.invitation }
                ).html_safe, 
                class: "nowrap size_20 patient-name"
              },   
              {header: "Status", content: helpers.format_status_and_attendance(ap), id: "status-#{ap.id}", class: helpers.status_class(ap) },          
              {header: "Confirmado", content: render_to_string(
                partial: 'clinic_management/services/confirmation_toggle',
                locals: { appointment: ap }
              )},
              {header: "Observações", content: render_to_string(partial: "clinic_management/shared/appointment_comments", locals: { appointment: ap, message: "" }), id: "appointment-comments-#{ap.id}"},
              {  
                header: "Telefone", 
                content: render_to_string(
                  partial: "clinic_management/leads/phone_with_message_tracking", 
                  locals: { lead: lead, appointment: ap }
                ).html_safe,
                class: "text-blue-500 hover:text-blue-700 nowrap"
              },          
              {header: "Receita", content: prescription_link(ap), class: "nowrap"},
              {header: "Ação", content: set_appointment_button(ap), id: "set-attendance-button-#{ap.id}", class: "pt-2 pb-0 nowrap" },          
              {header: "Tornar cliente", content: set_conversion_link(lead), class: "text-purple-500 nowrap"},
              {header: "Mensagem", content: generate_message_content(lead, ap), id: "whatsapp-link-#{lead.id.to_s}"},
              {header: "Mensagens enviadas:", content: ap&.messages_sent&.join(', '), id: "messages-sent-#{ap.id.to_s}"}            
            ]
          end
        end.compact # remove any nil entries resulting from next unless
      end

      def set_appointment_button(ap)
        if ap.attendance.present? || ap.status == "remarcado" || ap.service.date > Date.current
          "--"
        else
          helpers.button_to('Marcar como presente', set_attendance_appointment_path(ap), method: :patch, remote: true, class: "py-2 px-4 bg-blue-500 text-white rounded hover:bg-blue-700")
        end
      end

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
