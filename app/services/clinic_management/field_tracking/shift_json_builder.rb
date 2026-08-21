# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Serializes a FieldShift for JSON API responses.
    class ShiftJsonBuilder
      # @param shift [ClinicManagement::FieldShift]
      # @param include_points [Boolean]
      # @param since [Time, nil]
      # @param display_only [Boolean]
      # @return [Hash]
      def self.call(shift, include_points: false, since: nil, display_only: false)
        new(shift, include_points: include_points, since: since, display_only: display_only).call
      end

      def initialize(shift, include_points: false, since: nil, display_only: false)
        @shift = shift
        @include_points = include_points
        @since = since
        @display_only = display_only
      end

      def call
        payload = base_payload

        if @display_only
          payload[:display_points] = display_points_payload
        elsif @include_points
          payload[:points] = points_payload
        elsif @since.present?
          payload[:delta_points] = delta_points_payload
        end

        payload
      end

      private

      def base_payload
        last_point = @shift.last_track_point
        {
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
          ended_reason: @shift.ended_reason,
          last_point: last_point_hash(last_point)
        }
      end

      def points_payload
        @shift.field_track_points.chronological.map { |point| point_json(point) }
      end

      def delta_points_payload
        return [] unless @since.present?

        @shift.field_track_points
              .where("recorded_at > ?", @since)
              .order(recorded_at: :asc)
              .map { |point| point_json(point) }
      end

      def display_points_payload
        points = @shift.field_track_points.chronological.to_a
        RouteDisplaySimplifier.call(points).map { |point| point_json(point) }
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
