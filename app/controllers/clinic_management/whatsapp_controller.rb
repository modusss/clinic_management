# frozen_string_literal: true

module ClinicManagement
  # WhatsApp (Evolution instances) settings inside clinic Tailwind layout — Apenas Clínica mode.
  # ESSENTIAL: Mutations still POST to host EvolutionInstancesController routes via main_app.
  class WhatsappController < ApplicationController
    include EvolutionInstancesIndexData

    before_action :require_manager_above!
    before_action :require_whatsapp_integration_enabled!

    # GET /clinic_management/whatsapp
    def index
      prepare_evolution_instances_index!
    end

    private

    def require_manager_above!
      return if helpers.is_manager_above?

      redirect_to clinic_management.index_today_path, alert: "Você não tem permissão para acessar o WhatsApp."
    end

    def require_whatsapp_integration_enabled!
      return if current_account&.whatsapp_integration_enabled?

      redirect_to clinic_management.index_today_path,
                  alert: "Integração WhatsApp (Evolution) não está habilitada para esta conta."
    end
  end
end
