# frozen_string_literal: true

module ClinicManagement
  module LpvozCallProgramsHelper
    STATUS_LABELS = {
      "draft" => "Rascunho",
      "active" => "Ativa",
      "paused" => "Pausada"
    }.freeze

    OPERATION_STATUS_LABELS = {
      "queued" => "Na fila",
      "dispatching" => "Enviando",
      "accepted" => "Enviada",
      "in_progress" => "Em ligação",
      "completed" => "Concluída",
      "failed" => "Falha",
      "needs_attention" => "Precisa de atenção",
      "canceled" => "Cancelada"
    }.freeze

    OUTCOME_FILTER_OPTIONS = [
      ["Todos os resultados", ""],
      ["Reagendados", "rescheduled"],
      ["Sucesso", "success"],
      ["Não atenderam", "no_answer"],
      ["Falha técnica", "technical_failure"],
      ["Precisam de atenção", "attention"]
    ].freeze

    def lpvoz_program_status_label(program)
      STATUS_LABELS.fetch(program.status, program.status.humanize)
    end

    def lpvoz_program_status_classes(program)
      case program.status
      when "active" then "border-emerald-200 bg-emerald-50 text-emerald-700"
      when "paused" then "border-amber-200 bg-amber-50 text-amber-700"
      else "border-slate-200 bg-slate-100 text-slate-600"
      end
    end

    def lpvoz_operation_status_label(operation)
      return "Reagendado" if lpvoz_operation_outcome(operation) == "rescheduled"
      return "Sucesso" if lpvoz_operation_outcome(operation) == "success"
      return "Não atendeu" if lpvoz_operation_outcome(operation) == "no_answer"
      return "Falha técnica" if lpvoz_operation_outcome(operation) == "technical_failure"

      OPERATION_STATUS_LABELS.fetch(operation.status, operation.status.humanize)
    end

    def lpvoz_operation_status_classes(operation)
      case lpvoz_operation_outcome(operation)
      when "rescheduled", "success"
        return "border-emerald-200 bg-emerald-50 text-emerald-700"
      when "no_answer"
        return "border-slate-200 bg-slate-100 text-slate-600"
      when "technical_failure"
        return "border-rose-200 bg-rose-50 text-rose-700"
      end

      case operation.status
      when "completed" then "border-emerald-200 bg-emerald-50 text-emerald-700"
      when "in_progress", "accepted", "dispatching" then "border-blue-200 bg-blue-50 text-blue-700"
      when "failed", "needs_attention" then "border-amber-200 bg-amber-50 text-amber-700"
      else "border-slate-200 bg-slate-100 text-slate-600"
      end
    end

    def lpvoz_program_schedule(program)
      day_labels = %w[Dom Seg Ter Qua Qui Sex Sáb]
      days = program.weekdays.map { |day| day_labels.fetch(day) }.join(", ")
      windows = program.time_windows.map { |window| "#{window['start']}–#{window['end']}" }.join(" e ")
      "#{days} · #{windows}"
    end

    def lpvoz_program_agent_label(program, available_agents = [])
      agent = Array(available_agents).find { |entry| entry["key"] == program.agent_key }
      return program.agent_key unless agent

      version = agent["version"].present? ? " · versão ativa v#{agent['version']}" : ""
      "#{agent['name']}#{version}"
    end

    def lpvoz_operation_result(operation)
      if lpvoz_operation_outcome(operation) == "rescheduled"
        scheduled_at = Time.zone.parse(operation.result["scheduled_at"].to_s) rescue nil
        return scheduled_at ? "Reagendado · #{l(scheduled_at, format: '%d/%m, %H:%M')}" : "Reagendado"
      end

      if operation.result["provider_error"].present?
        return "Falha técnica: #{operation.result['provider_error']} #{operation.result['automatic_pause_reason']}".squish
      end

      operation.result["summary"].presence || operation.last_error.presence || "Sem resultado informado"
    end

    def lpvoz_operation_outcome(operation)
      result = operation.result || {}
      classification = result["classification"].to_s
      integration_result = result.dig("collected_data", "integration_result").to_s

      return "rescheduled" if result["rescheduled"] == true || integration_result == "rescheduled"
      return "success" if classification == "confirmed"
      return "no_answer" if classification.in?(%w[no_answer voicemail]) || result["outcome"].to_s.in?(%w[no_answer voicemail])
      return "technical_failure" if classification == "technical_failure" || result["provider_error"].present?

      operation.status
    end

    def lpvoz_operation_transcript(operation)
      Array(operation.result["transcript"]).filter_map do |turn|
        next unless turn.is_a?(Hash) && turn["message"].present?

        {
          role: turn["role"] == "agent" ? "Atendente" : "Paciente",
          message: turn["message"]
        }
      end
    end
  end
end
