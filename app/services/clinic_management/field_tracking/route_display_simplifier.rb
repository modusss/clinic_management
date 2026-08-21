# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Reduces GPS samples for map rendering while preserving route shape endpoints.
    class RouteDisplaySimplifier
      DEFAULT_LIMIT = 400

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
        return @points if @points.size <= @limit
        return @points if @limit < 2

        step = (@points.size - 1).to_f / (@limit - 1)
        selected_indices = (0...@limit).map { |index| (index * step).round }
        selected_indices[0] = 0
        selected_indices[-1] = @points.size - 1

        selected_indices.uniq.sort.map { |index| @points[index] }
      end
    end
  end
end
