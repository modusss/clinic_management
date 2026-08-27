# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class RunCallProgramsJob < ApplicationJob
      queue_as :default

      # The OS cron invokes this lightweight orchestrator once per minute. Each
      # program receives its own executor job so one clinic cannot delay others.
      def perform
        ClinicManagement::LpvozCallProgram.active.find_each do |program|
          ClinicManagement::Lpvoz::DispatchNextProgramCallJob.perform_later(program.id)
        end
      end
    end
  end
end
