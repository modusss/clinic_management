# frozen_string_literal: true

module ClinicManagement
  class LpvozIntegrationsController < ApplicationController
    before_action :require_lpvoz_feature
    before_action :require_manager
    before_action :set_connection

    def show
      return unless @connection.active?

      @programs = @connection.lpvoz_call_programs.includes(:lpvoz_operations).recent_first
      operations_today = @connection.lpvoz_operations.where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
      @overview = {
        active_programs: @programs.count(&:active?),
        in_progress: operations_today.where(status: LpvozCallProgram::ACTIVE_OPERATION_STATUSES).count,
        completed: operations_today.where(status: LpvozCallProgram::TERMINAL_OPERATION_STATUSES).count,
        rescheduled: operations_today.where("result @> ?", { rescheduled: true }.to_json).count
      }
      @available_agents = available_agents
    end

    def enable
      @connection.update!(status: :pending, permissions: LpvozConnection::PERMISSIONS)
      redirect_to lpvoz_integration_path, notice: "Integração habilitada. Gere um código temporário para conectar o LPVoz."
    end

    def generate_pairing_code
      @pairing_code = @connection.generate_pairing_code!

      respond_to do |format|
        format.html { render :show, status: :ok }
        format.turbo_stream
      end
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

    def available_agents
      ClinicManagement::Lpvoz::Client.new(connection: @connection).available_agents
    rescue ClinicManagement::Lpvoz::Client::RequestFailed, KeyError => error
      Rails.logger.warn("[LPVoz integration] Agent catalog unavailable: #{error.message}")
      []
    end
  end
end
