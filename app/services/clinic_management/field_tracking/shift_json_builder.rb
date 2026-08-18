# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Serializes a FieldShift for JSON API responses.
    class ShiftJsonBuilder
      # @param shift [ClinicManagement::FieldShift]
      # @param include_points [Boolean]
      # @return [Hash]
      def self.call(shift, include_points: false)
        new(shift, include_points: include_points).call
      end

      def initialize(shift, include_points: false)
        @shift = shift
        @include_points = include_points
      end

      def call
        payload = {
          id: @shift.id,
          status: @shift.status,
          referral_id: @shift.referral_id,
          started_at: @shift.started_at&.iso8601,
          ended_at: @shift.ended_at&.iso8601,
          points_count: @shift.points_count,
          distance_meters: @shift.distance_meters,
          duration_seconds: @shift.duration_seconds,
          avg_speed_kmh: @shift.avg_speed_kmh&.to_f,
          avg_accuracy_meters: @shift.avg_accuracy_meters&.to_f,
          device_metadata: @shift.device_metadata,
          ended_reason: @shift.ended_reason
        }

        if @include_points
          payload[:points] = @shift.field_track_points.chronological.map { |point| point_json(point) }
        end

        payload
      end

      private

      def point_json(point)
        {
          id: point.id,
          client_point_id: point.client_point_id,
          recorded_at: point.recorded_at.iso8601,
          latitude: point.latitude.to_f,
          longitude: point.longitude.to_f,
          accuracy_meters: point.accuracy_meters&.to_f,
          speed_mps: point.speed_mps&.to_f,
          bearing: point.bearing&.to_f
        }
      end
    end
  end
end
