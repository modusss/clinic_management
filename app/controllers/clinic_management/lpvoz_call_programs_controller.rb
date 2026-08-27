# frozen_string_literal: true

module ClinicManagement
  class LpvozCallProgramsController < ApplicationController
    before_action :require_lpvoz_feature
    before_action :require_manager
    before_action :set_connection
    before_action :set_program, only: %i[show edit update destroy activate pause]
    before_action :load_available_agents, only: :show
    before_action :load_form_options, only: %i[new create edit update]

    def index
      redirect_to lpvoz_integration_path
    end

    def show
      @view = params[:view].in?(%w[queue results]) ? params[:view] : "queue"
      operations = @program.lpvoz_operations
        .includes(:lead, appointment: :service)
        .select(
          "clinic_management_lpvoz_operations.*",
          <<~SQL.squish
            (
              SELECT COUNT(*)
              FROM clinic_management_lpvoz_operations prior_operation
              WHERE prior_operation.lpvoz_call_program_id = clinic_management_lpvoz_operations.lpvoz_call_program_id
                AND prior_operation.lead_id = clinic_management_lpvoz_operations.lead_id
                AND (
                  prior_operation.created_at < clinic_management_lpvoz_operations.created_at
                  OR (
                    prior_operation.created_at = clinic_management_lpvoz_operations.created_at
                    AND prior_operation.id <= clinic_management_lpvoz_operations.id
                  )
                )
            ) AS attempt_number
          SQL
        )
      operations = operations.where(status: LpvozCallProgram::TERMINAL_OPERATION_STATUSES) if @view == "results"
      if params[:status].in?(ClinicManagement::LpvozOperation.statuses.keys)
        operations = operations.where(status: params[:status])
      end
      operations = filter_by_outcome(operations, params[:outcome])
      if params[:q].present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
        operations = operations.joins(:lead).where(
          "clinic_management_leads.name ILIKE :query OR clinic_management_leads.phone ILIKE :query",
          query:
        )
      end
      @operations = operations
        .recent_first
        .page(params[:page])
        .per(25)
      @today_scope = @program.lpvoz_operations.where(created_at: @program.local_day_range)
      @status_counts = @today_scope.group(:status).count
      @outcome_counts = {
        success: filter_by_outcome(@today_scope, "success").count,
        rescheduled: filter_by_outcome(@today_scope, "rescheduled").count,
        no_answer: filter_by_outcome(@today_scope, "no_answer").count,
        attention: filter_by_outcome(@today_scope, "attention").count
      }
      @eligible_count = ClinicManagement::Lpvoz::EligiblePatientsQuery.new(program: @program).count
    end

    def new
      @program = @connection.lpvoz_call_programs.new(
        account: current_account,
        created_by: current_user,
        agent_key: @connection.agent_key,
        weekdays: [1, 2, 3, 4, 5],
        time_windows: ClinicManagement::LpvozCallProgram::DEFAULT_TIME_WINDOWS,
        filters: ClinicManagement::LpvozCallProgram::DEFAULT_FILTERS,
        daily_limit: 100
      )
    end

    def create
      @program = @connection.lpvoz_call_programs.new(program_params)
      @program.account = current_account
      @program.created_by = current_user

      if agent_available?(@program.agent_key) && @program.save
        redirect_to @program, notice: "Programação salva como rascunho. Revise e ative quando estiver pronta."
      else
        @program.errors.add(:agent_key, "não está disponível nesta integração") unless agent_available?(@program.agent_key)
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      @program.assign_attributes(program_params)
      if agent_available?(@program.agent_key) && @program.save
        redirect_to @program, notice: "Programação atualizada."
      else
        @program.errors.add(:agent_key, "não está disponível nesta integração") unless agent_available?(@program.agent_key)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @program.lpvoz_operations.exists?
        redirect_to @program, alert: "Uma programação com histórico não pode ser excluída. Pause-a para impedir novas ligações."
      else
        @program.destroy!
        redirect_to lpvoz_integration_path, notice: "Programação excluída."
      end
    end

    def activate
      load_available_agents
      unless agent_available?(@program.agent_key)
        return redirect_to @program, alert: "O agente selecionado não está publicado ou não está mais vinculado à integração."
      end

      @program.activate!
      ClinicManagement::Lpvoz::DispatchNextProgramCallJob.perform_later(@program.id)
      redirect_to @program, notice: "Programação ativada. As ligações começarão dentro da próxima janela configurada."
    end

    def pause
      @program.pause!
      redirect_to @program, notice: "Programação pausada. Nenhuma nova ligação será iniciada."
    end

    def preview
      program = @connection.lpvoz_call_programs.new(program_params)
      program.account = current_account
      if program.valid?
        count = ClinicManagement::Lpvoz::EligiblePatientsQuery.new(program:).count
        render json: { count:, label: count == 1 ? "paciente elegível" : "pacientes elegíveis" }
      else
        render json: { error: program.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    private

    def require_lpvoz_feature
      return if lpvoz_integration_enabled?

      redirect_to root_path, alert: "Integração LPVoz não está habilitada para esta conta."
    end

    def require_manager
      return if lpvoz_program_management_allowed?

      redirect_to root_path, alert: "Apenas gestores podem configurar programações de ligação."
    end

    def set_connection
      @connection = ClinicManagement::LpvozConnection.active.find_by(account: current_account)
      redirect_to lpvoz_integration_path, alert: "Conecte o LPVoz antes de configurar programações." unless @connection
    end

    def set_program
      @program = ClinicManagement::LpvozCallProgram.find_by!(id: params[:id], account: current_account)
    end

    def load_form_options
      load_available_agents
      @regions = ClinicManagement::Region.active.order(:name)
      @service_locations = ClinicManagement::ServiceLocation.order(:name)
    end

    def load_available_agents
      @agent_catalog_available = true
      @available_agents = ClinicManagement::Lpvoz::Client.new(connection: @connection).available_agents
    rescue ClinicManagement::Lpvoz::Client::RequestFailed, KeyError => error
      Rails.logger.warn("[LPVoz programs] Agent catalog unavailable: #{error.message}")
      @agent_catalog_available = false
      @available_agents = [{
        "key" => @connection.agent_key,
        "name" => "Agente conectado",
        "version" => nil,
        "provider" => "elevenlabs"
      }]
    end

    def agent_available?(agent_key)
      @agent_catalog_available && Array(@available_agents).any? { |agent| agent["key"] == agent_key }
    end

    def filter_by_outcome(scope, outcome)
      case outcome
      when "rescheduled"
        scope.where("result @> ? OR result #>> '{collected_data,integration_result}' = 'rescheduled'", { rescheduled: true }.to_json)
      when "success"
        scope.where("result ->> 'classification' = 'confirmed' OR result @> ? OR result #>> '{collected_data,integration_result}' = 'rescheduled'", { rescheduled: true }.to_json)
      when "no_answer"
        scope.where("result ->> 'classification' IN (?) OR result ->> 'outcome' IN (?)", %w[no_answer voicemail], %w[no_answer voicemail])
      when "technical_failure"
        scope.where("result ->> 'classification' = 'technical_failure' OR NULLIF(result ->> 'provider_error', '') IS NOT NULL")
      when "attention"
        scope.where(status: %w[failed needs_attention])
      else
        scope
      end
    end

    def program_params
      params.require(:lpvoz_call_program).permit(
        :name,
        :agent_key,
        :time_zone,
        :daily_limit,
        weekdays: [],
        time_windows: %i[start end],
        filters: [:patient_type, :period_days, :region_id, :service_location_id, :interest_status, { lpvoz_statuses: [] }]
      )
    end
  end
end
