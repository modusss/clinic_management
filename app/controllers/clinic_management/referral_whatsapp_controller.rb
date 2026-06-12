# frozen_string_literal: true

module ClinicManagement
  # Captador personal WhatsApp connections inside clinic Tailwind layout (Apenas Clínica).
  # ESSENTIAL: Mutations still POST to host ReferralEvolutionInstancesController via main_app.
  class ReferralWhatsappController < ApplicationController
    skip_before_action :redirect_referral_users

    prepend_before_action :redirect_full_retail_referral_whatsapp_to_host
    before_action :require_whatsapp_integration_enabled!
    before_action :set_referral
    before_action :ensure_referral_user!
    before_action :ensure_can_connect_whatsapp!

    # GET /clinic_management/meu-whatsapp
    def index
      prepare_connection_stats!
    end

    private

    # ESSENTIAL: With retail module on, captador WhatsApp stays on host Materialize UI.
    def redirect_full_retail_referral_whatsapp_to_host
      return if current_account&.clinic_only?

      redirect_to main_app.referrals_connection_path
    end

    def set_referral
      @referral = helpers.user_referral
    end

    def require_whatsapp_integration_enabled!
      return if whatsapp_integration_enabled?

      redirect_to helpers.referral_clinic_home_path,
                  alert: "Integração WhatsApp (Evolution) não está habilitada para esta conta."
    end

    def ensure_referral_user!
      return if helpers.referral?(current_user)

      redirect_to clinic_management.index_today_path, alert: "Acesso não autorizado."
    end

    def ensure_can_connect_whatsapp!
      return if @referral&.can_connect_whatsapp

      redirect_to helpers.referral_clinic_home_path,
                  alert: "Você não tem permissão para conectar o WhatsApp. Entre em contato com o administrador."
    end

    # ESSENTIAL: Same stats as retail Referrals::ConnectionController#index — keep in sync.
    def prepare_connection_stats!
      instances = @referral.evolution_instances.order(created_at: :desc)
      @instances = instances
      @connected_count = instances.connected.count
      @total_count = instances.count
      @pending_count = instances.where(connected: false).count
      @has_legacy = @referral.evolution_instance_name.present? &&
                    !instances.exists?(instance_name: @referral.evolution_instance_name)
      @total_with_legacy = @total_count + (@has_legacy ? 1 : 0)
      @connected_with_legacy = @connected_count + (@has_legacy && @referral.instance_connected ? 1 : 0)
      @can_add_instance = @total_count.zero? || (@connected_count.positive? && @pending_count.zero?)
    end
  end
end
