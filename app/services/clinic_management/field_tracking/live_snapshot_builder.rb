# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Builds JSON payload for the live map polling endpoint (field_tracking#index.json).
    class LiveSnapshotBuilder
      # @param active_shifts [Enumerable<ClinicManagement::FieldShift>]
      # @return [Hash]
      def self.call(active_shifts)
        new(active_shifts).call
      end

      def initialize(active_shifts)
        @active_shifts = active_shifts
      end

      def call
        {
          generated_at: Time.current.iso8601,
          shifts: @active_shifts.map { |shift| shift_payload(shift) }
        }
      end

      private

      def shift_payload(shift)
        payload = ShiftJsonBuilder.call(shift)
        payload[:referral_name] = shift.referral&.name
        payload[:last_point] = last_point_hash(shift.last_track_point)
        payload
      end

      def last_point_hash(point)
        return nil unless point

        {
          latitude: point.latitude.to_f,
          longitude: point.longitude.to_f,
          recorded_at: point.recorded_at.iso8601,
          accuracy_meters: point.accuracy_meters&.to_f
        }
      end
    end
  end
end
