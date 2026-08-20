# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Builds JSON payload for the live map polling endpoint (field_tracking#index.json).
    class LiveSnapshotBuilder
      FRESH_SIGNAL_WINDOW = 2.minutes
      RECENT_POINTS_LIMIT = 120

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
        last_point = shift.last_track_point
        payload = ShiftJsonBuilder.call(shift)
        payload[:referral_name] = shift.referral&.name
        payload[:last_point] = last_point_hash(last_point)
        payload[:last_update_seconds] = last_update_seconds(last_point)
        payload[:signal_status] = signal_status(last_point)
        payload[:recent_points] = recent_points(shift)
        payload
      end

      def last_update_seconds(point)
        return nil unless point

        [(Time.current - point.recorded_at).to_i, 0].max
      end

      def signal_status(point)
        return "waiting" unless point

        last_update_seconds(point) <= FRESH_SIGNAL_WINDOW.to_i ? "fresh" : "delayed"
      end

      def recent_points(shift)
        shift.field_track_points
             .order(recorded_at: :desc)
             .limit(RECENT_POINTS_LIMIT)
             .reverse
             .map { |point| point_hash(point) }
      end

      def last_point_hash(point)
        return nil unless point

        point_hash(point)
      end

      def point_hash(point)
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
