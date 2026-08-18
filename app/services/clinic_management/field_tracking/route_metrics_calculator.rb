# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Computes distance and averages for a completed or active shift.
    class RouteMetricsCalculator
      EARTH_RADIUS_M = 6_371_000

      # @param shift [ClinicManagement::FieldShift]
      # @return [Hash] metric keys for FieldShift update
      def self.call(shift)
        new(shift).call
      end

      def initialize(shift)
        @shift = shift
      end

      def call
        points = @shift.field_track_points.chronological.to_a
        distance_meters = total_distance_meters(points)
        duration_seconds = duration_seconds_for_shift
        avg_speed_kmh = average_speed_kmh(points, distance_meters, duration_seconds)
        avg_accuracy_meters = average_accuracy(points)

        {
          distance_meters: distance_meters,
          duration_seconds: duration_seconds,
          avg_speed_kmh: avg_speed_kmh,
          avg_accuracy_meters: avg_accuracy_meters
        }
      end

      private

      def duration_seconds_for_shift
        end_time = @shift.ended_at || Time.current
        return 0 unless @shift.started_at

        [(end_time - @shift.started_at).to_i, 0].max
      end

      def total_distance_meters(points)
        return 0 if points.size < 2

        points.each_cons(2).sum do |a, b|
          haversine_meters(a.latitude.to_f, a.longitude.to_f, b.latitude.to_f, b.longitude.to_f)
        end.round
      end

      def average_speed_kmh(points, distance_meters, duration_seconds)
        speeds = points.filter_map { |p| p.speed_mps&.to_f }.select(&:positive?)
        if speeds.any?
          return ((speeds.sum / speeds.size) * 3.6).round(2)
        end

        return nil if duration_seconds.to_i <= 0

        ((distance_meters.to_f / duration_seconds) * 3.6).round(2)
      end

      def average_accuracy(points)
        values = points.filter_map { |p| p.accuracy_meters&.to_f }.select(&:positive?)
        return nil if values.empty?

        (values.sum / values.size).round(2)
      end

      # Haversine distance between two lat/lng pairs in meters.
      def haversine_meters(lat1, lon1, lat2, lon2)
        lat1_rad = lat1 * Math::PI / 180
        lat2_rad = lat2 * Math::PI / 180
        dlat = (lat2 - lat1) * Math::PI / 180
        dlon = (lon2 - lon1) * Math::PI / 180

        a = Math.sin(dlat / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon / 2)**2
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        EARTH_RADIUS_M * c
      end
    end
  end
end
