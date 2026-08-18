# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # ESSENTIAL: Recomputes route metrics when a shift ends (non-blocking via GoodJob).
    class ShiftSummaryJob < ClinicManagement::ApplicationJob
      queue_as :default

      # @param shift_id [Integer]
      def perform(shift_id)
        shift = ClinicManagement::FieldShift.find_by(id: shift_id)
        return unless shift

        metrics = RouteMetricsCalculator.call(shift)
        shift.update!(metrics)
      end
    end
  end
end
