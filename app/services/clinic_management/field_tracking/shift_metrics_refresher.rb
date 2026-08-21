# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Recomputes and persists route metrics on a FieldShift.
    # ESSENTIAL: Active shifts need live metrics; completed shifts use the same path
    # via ShiftSummaryJob on end — this service is the single calculation entry point.
    class ShiftMetricsRefresher
      STALE_AFTER = 60.seconds

      # @param shift [ClinicManagement::FieldShift]
      # @return [ClinicManagement::FieldShift]
      def self.call(shift)
        new(shift).call
      end

      # @param shift [ClinicManagement::FieldShift]
      # @return [Boolean] true when metrics were stale and got refreshed
      def self.refresh_if_stale!(shift)
        new(shift).refresh_if_stale!
      end

      def initialize(shift)
        @shift = shift
      end

      def call
        metrics = RouteMetricsCalculator.call(@shift)
        @shift.update!(metrics)
        @shift
      end

      # @return [Boolean]
      def refresh_if_stale!
        return false unless stale?

        call
        true
      end

      private

      def stale?
        return true if @shift.distance_meters.nil? && @shift.points_count.to_i.positive?
        return true if @shift.active? && @shift.updated_at < STALE_AFTER.ago

        false
      end
    end
  end
end
