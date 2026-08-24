# frozen_string_literal: true

module ClinicManagement
  class LpvozIntegrationsController < ApplicationController
    before_action :require_lpvoz_feature
    before_action :require_manager
    before_action :set_connection

    def show; end

    def enable
      @connection.update!(status: :pending, permissions: LpvozConnection::PERMISSIONS)
      redirect_to lpvoz_integration_path, notice: "Integração habilitada. Gere um código temporário para conectar o LPVoz."
    end

    def generate_pairing_code
      @pairing_code = @connection.generate_pairing_code!
      render :show, status: :ok
    end

    def revoke
      @connection.revoke!
      redirect_to lpvoz_integration_path, notice: "Acesso do LPVoz revogado."
    end

    private

    def require_lpvoz_feature
      return if lpvoz_integration_enabled?

      redirect_to root_path, alert: "Integração LPVoz não está habilitada para esta conta."
    end

    def require_manager
      return if is_manager_above?

      redirect_to root_path, alert: "Apenas gestores podem configurar esta integração."
    end

    def set_connection
      @connection = LpvozConnection.find_or_create_by!(account: current_account) do |connection|
        connection.permissions = LpvozConnection::PERMISSIONS
      end
    end
  end
end
