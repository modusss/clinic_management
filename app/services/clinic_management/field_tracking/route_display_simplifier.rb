# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Reduces GPS samples for map rendering while preserving route shape endpoints.
    class RouteDisplaySimplifier
      DEFAULT_LIMIT = 400
      STATIONARY_COLLAPSE_METERS = 15
      EARTH_RADIUS_METERS = 6_371_000

      # @param points [Array<#latitude, #longitude>]
      # @param limit [Integer]
      # @return [Array]
      def self.call(points, limit: DEFAULT_LIMIT)
        new(points, limit: limit).call
      end

      def initialize(points, limit: DEFAULT_LIMIT)
        @points = Array(points)
        @limit = limit
      end

      def call
        collapsed = collapse_stationary_points(@points)
        return collapsed if collapsed.size <= @limit
        return collapsed if @limit < 2

        decimate_evenly(collapsed)
      end

      private

      # Removes consecutive jitter samples that stay within the stationary radius.
      def collapse_stationary_points(points)
        return points if points.size < 2

        collapsed = [points.first]
        points.each_cons(2) do |previous, current|
          collapsed << current unless within_stationary_radius?(previous, current)
        end
        collapsed
      end

      def within_stationary_radius?(first, second)
        distance_meters(first, second) < STATIONARY_COLLAPSE_METERS
      end

      def decimate_evenly(points)
        step = (points.size - 1).to_f / (@limit - 1)
        selected_indices = (0...@limit).map { |index| (index * step).round }
        selected_indices[0] = 0
        selected_indices[-1] = points.size - 1

        selected_indices.uniq.sort.map { |index| points[index] }
      end

      def distance_meters(first, second)
        lat1 = latitude(first)
        lon1 = longitude(first)
        lat2 = latitude(second)
        lon2 = longitude(second)

        lat1_rad = lat1 * Math::PI / 180
        lat2_rad = lat2 * Math::PI / 180
        dlat = (lat2 - lat1) * Math::PI / 180
        dlon = (lon2 - lon1) * Math::PI / 180

        haversine = Math.sin(dlat / 2)**2 +
                    Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon / 2)**2

        EARTH_RADIUS_METERS * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
      end

      def latitude(point)
        value = point.respond_to?(:latitude) ? point.latitude : point[:latitude]
        value.to_f
      end

      def longitude(point)
        value = point.respond_to?(:longitude) ? point.longitude : point[:longitude]
        value.to_f
      end
    end
  end
end
