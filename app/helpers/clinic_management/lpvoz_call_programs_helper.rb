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
      OPERATION_STATUS_LABELS.fetch(operation.status, operation.status.humanize)
    end

    def lpvoz_operation_status_classes(operation)
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
      if operation.result["rescheduled"]
        scheduled_at = Time.zone.parse(operation.result["scheduled_at"].to_s) rescue nil
        return scheduled_at ? "Reagendado · #{l(scheduled_at, format: '%d/%m, %H:%M')}" : "Reagendado"
      end

      operation.result["summary"].presence || operation.last_error.presence || "Sem resultado informado"
    end
  end
end
