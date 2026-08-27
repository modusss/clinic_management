# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class DispatchNextProgramCallJob < ApplicationJob
      queue_as :default

      MAX_ACTIVE_DURATION = 60.minutes

      def perform(program_id, now: Time.current)
        program = ClinicManagement::LpvozCallProgram.find(program_id)
        operation = nil

        program.with_lock do
          return unless program.active?
          return unless program.account.lpvoz_integration_available?
          return unless program.lpvoz_connection.active?
          return unless program.within_call_window?(now)
          return if program.daily_limit_reached?(now)

          close_stale_operations(program, now:)
          return if program.active_operation?

          candidate = ClinicManagement::Lpvoz::EligiblePatientsQuery.new(program:).next_candidate
          return unless candidate

          appointment = ClinicManagement::Appointment.find(candidate.current_appointment_id)
          operation = program.lpvoz_operations.create!(
            account: program.account,
            lpvoz_connection: program.lpvoz_connection,
            lead: candidate,
            appointment:,
            agent_key: program.agent_key
          )
          program.update!(last_dispatched_at: now)
        end

        ClinicManagement::Lpvoz::DispatchOperationJob.perform_later(operation.id) if operation
      end

      private

      def close_stale_operations(program, now:)
        program.lpvoz_operations
          .where(status: ClinicManagement::LpvozCallProgram::ACTIVE_OPERATION_STATUSES)
          .where("updated_at < ?", now - MAX_ACTIVE_DURATION)
          .update_all(
            status: "needs_attention",
            last_error: "Ligação sem atualização por mais de 60 minutos.",
            completed_at: now,
            updated_at: now
          )
      end
    end
  end
end
