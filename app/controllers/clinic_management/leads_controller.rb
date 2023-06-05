module ClinicManagement
  class LeadsController < ApplicationController
    before_action :set_lead, only: %i[ show edit update destroy ]
    before_action :set_menu, only: %i[ index absent attended cancelled ]
    skip_before_action :redirect_referral_users, only: [:destroy]

    include GeneralHelper

    # GET /leads
    def index
      @leads = Lead.includes(:invitations, :appointments).page(params[:page]).per(50)  # 10 leads por página
      @rows = load_leads_data(@leads)
    end
    
    # GET /leads/1
    def show
      @rows = get_lead_data
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
      # Use `fallback_location` to handle cases where the referrer is missing or invalid.
      redirect_back(fallback_location: root_path, notice: 'Convite excluido com sucesso.')
    end

    def absent
      @leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ?', false).page(params[:page]).per(50)
      @rows = load_leads_data(@leads)
      render :index
    end
    
    def attended
      @leads = fetch_leads_by_appointment_condition('clinic_management_appointments.attendance = ?', true).page(params[:page]).per(50)
      @rows = load_leads_data(@leads)
      render :index
    end
    
    def cancelled
      @leads = fetch_leads_by_appointment_condition('clinic_management_appointments.status = ?', 'cancelado').page(params[:page]).per(50)
      @rows = load_leads_data(@leads)
      render :index
    end
    
    
    private

    def generate_message_content(lead, appointment)
      render_to_string(
        partial: "clinic_management/lead_messages/lead_message_form",
        locals: { lead: lead, appointment: appointment }
      )
    end

    def get_lead_data
      @lead.appointments.map.with_index do |ap, index|
        invitation = ap.invitation
        [
          {header: "#", content: index + 1},
          {header: "Paciente", content: invitation.patient_name },
          {header: "Data do atendimento", content: helpers.link_to(invite_day(ap), service_path(ap.service), class: "text-blue-500 hover:text-blue-700")},         
          {header: "Comparecimento", content: (ap.attendance == true ? "Sim" : "Não"), class: helpers.attendance_class(ap)},
          {header: "Status", content: ap.status, class: helpers.status_class(ap)},
          {header: "Data do convite", content: invitation.created_at.strftime("%d/%m/%Y")},
          {header: "Convidado por", content: invitation.referral.name},
          {header: "Região", content: invitation.region.name},
          {header: "Mensagem", content: generate_message_content(@lead, ap), id: "whatsapp-link-#{@lead.id}" }
        ]
      end
    end

    def set_menu
      @menu = [
        {url_name: 'Todos', url: 'leads', controller_name: 'leads', action_name: 'index'},
        {url_name: 'Ausentes', url: 'absent_leads', controller_name: 'leads', action_name: 'absent'},
        {url_name: 'Compareceram', url: 'attended_leads', controller_name: 'leads', action_name: 'attended'},
        {url_name: 'Cancelados', url: 'cancelled_leads', controller_name: 'leads', action_name: 'cancelled'}
      ]
    end

    def load_leads_data(leads)
      leads.map.with_index do |lead, index|
        last_invitation = lead.invitations.last
        last_appointment = lead.appointments.last
        [
          {header: "Ordem", content: index + 1},
          {header: "Paciente", content: helpers.link_to(lead.name, lead_path(lead), class: "text-blue-500 hover:text-blue-700", target: "_blank" )},
          {header: "Responsável", content: responsible_content(last_invitation)},
          {header: "Telefone", content: lead.phone},
          {header: "Último indicador", content: last_referral(last_invitation)},
          {header: "Qtd. de convites", content: lead.invitations.count},
          {header: "Qtd. de atendimentos", content: lead.appointments.count},
          {header: "Último atendimento", content: last_appointment_link(last_appointment)},
          {header: "Mensagem", content: generate_message_content(lead, last_appointment), id: "whatsapp-link-#{lead.id}" }          ]
      end
    end

    def last_referral(last_invitation)
      last_invitation&.referral&.name || ""
    end

    def last_appointment_link(last_appointment)
      last_appointment.present? ? helpers.link_to("#{last_appointment.status} - #{invite_day(last_appointment)}", service_path(last_appointment.service), class: "text-blue-500 hover:text-blue-700", target: "_blank") : ""
    end
    
    
      def responsible_content(invite)
        if invite.present?
          (invite.lead.name != invite.patient_name) ? invite.lead.name : ""
        else
          ""
        end
      end

      def fetch_leads_by_appointment_condition(query_condition, value)
        ClinicManagement::Lead.where(id: ClinicManagement::Appointment.where(query_condition, value).select(:lead_id))
                              .where('last_appointment_id IN (?)', ClinicManagement::Appointment.where(query_condition, value).pluck(:id))
      end   
              
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
