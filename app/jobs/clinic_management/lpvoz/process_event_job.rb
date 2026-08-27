# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class ProcessEventJob < ApplicationJob
      queue_as :default

      STATUS_MAP = {
        "voice_operation.accepted" => "accepted",
        "call.queued" => "accepted",
        "call.ringing" => "in_progress",
        "call.in_progress" => "in_progress",
        # Technical hangup is not the business result; wait for call.outcome_ready.
        "call.completed" => "in_progress",
        "call.failed" => "failed",
        "call.outcome_ready" => "completed"
      }.freeze

      STATUS_RANK = {
        "queued" => 0,
        "dispatching" => 1,
        "accepted" => 2,
        "in_progress" => 3,
        "completed" => 4,
        "needs_attention" => 4,
        "failed" => 4,
        "canceled" => 4
      }.freeze

      def perform(event_id)
        event = ClinicManagement::LpvozEvent.find(event_id)
        return if event.processed?

        event.update!(status: :processing, last_error: nil)
        operation = event.lpvoz_operation
        payload = event.payload.deep_stringify_keys
        data = payload.fetch("data", {})
        candidate = STATUS_MAP.fetch(event.event_type, operation.status)
        candidate = "needs_attention" if data["needs_review"] == true
        quota_exceeded = quota_exceeded?(data)
        candidate = "needs_attention" if quota_exceeded
        pause_program_for_quota!(operation) if quota_exceeded
        next_status = if operation.terminal?
          operation.status
        elsif STATUS_RANK.fetch(candidate) >= STATUS_RANK.fetch(operation.status)
          candidate
        else
          operation.status
        end
        result = operation.result.merge(
          "last_event" => payload.slice("event_type", "occurred_at"),
          "summary" => data["summary"].presence || operation.result["summary"],
          "classification" => (quota_exceeded ? "technical_failure" : data["classification"].presence) || operation.result["classification"],
          "identity_status" => data["identity_status"].presence || operation.result["identity_status"],
          "collected_data" => merged_collected_data(operation, data),
          "transcript" => normalized_transcript(data["transcript"]).presence || operation.result["transcript"],
          "next_action" => data["next_action"].presence || operation.result["next_action"],
          "provider_error" => ("Cota do ElevenLabs esgotada." if quota_exceeded) || operation.result["provider_error"],
          "automatic_pause_reason" => ("Programação pausada automaticamente porque a cota do ElevenLabs foi excedida." if quota_exceeded) || operation.result["automatic_pause_reason"]
        ).compact
        operation.update!(
          voice_operation_id: payload["voice_operation_id"].presence || operation.voice_operation_id,
          agent_key: operation.agent_key.presence || operation.lpvoz_connection.agent_key,
          status: next_status,
          result:,
          last_error: quota_exceeded ? "Cota do ElevenLabs esgotada." : operation.last_error,
          completed_at: next_status.in?(%w[completed failed needs_attention]) ? Time.current : operation.completed_at
        )
        event.update!(status: :processed, processed_at: Time.current)
      rescue StandardError => error
        event&.update!(status: :failed, last_error: error.message)
        raise
      end

      private

      def merged_collected_data(operation, data)
        existing = operation.result["collected_data"]
        incoming = data["collected_data"]
        (existing.is_a?(Hash) ? existing : {}).merge(incoming.is_a?(Hash) ? incoming : {})
      end

      def normalized_transcript(raw)
        return [] unless raw.is_a?(Array)

        raw.first(100).filter_map do |turn|
          next unless turn.is_a?(Hash)

          role = turn["role"].to_s.first(30)
          message = turn["message"].to_s.strip.first(2_000)
          next if role.blank? || message.blank?

          { "role" => role, "message" => message }
        end
      end

      def quota_exceeded?(data)
        candidates = [
          data["failure_reason"],
          data["summary"],
          data.dig("collected_data", "failure_reason"),
          data.dig("collected_data", "termination_reason")
        ]
        candidates.compact.any? { |value| value.to_s.match?(/quota(?: limit)?|exceeds your quota/i) }
      end

      def pause_program_for_quota!(operation)
        program = operation.lpvoz_call_program
        return unless program&.active?

        program.pause!
        Rails.logger.error("[LPVoz programs] Program #{program.id} paused: ElevenLabs quota exceeded")
      end
    end
  end
end
