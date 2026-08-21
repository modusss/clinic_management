# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # ESSENTIAL: Non-blocking metrics refresh for active shifts after GPS batch ingestion.
    class ShiftMetricsRefreshJob < ClinicManagement::ApplicationJob
      queue_as :default

      # @param shift_id [Integer]
      def perform(shift_id)
        shift = ClinicManagement::FieldShift.find_by(id: shift_id)
        return unless shift&.active?

        ShiftMetricsRefresher.call(shift)
      end
    end
  end
end
