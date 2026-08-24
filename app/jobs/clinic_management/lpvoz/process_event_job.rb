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
          "classification" => data["classification"].presence || operation.result["classification"]
        ).compact
        operation.update!(
          voice_operation_id: payload["voice_operation_id"].presence || operation.voice_operation_id,
          status: next_status,
          result:,
          completed_at: next_status.in?(%w[completed failed needs_attention]) ? Time.current : operation.completed_at
        )
        event.update!(status: :processed, processed_at: Time.current)
      rescue StandardError => error
        event&.update!(status: :failed, last_error: error.message)
        raise
      end
    end
  end
end
