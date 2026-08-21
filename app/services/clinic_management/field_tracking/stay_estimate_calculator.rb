# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Estimates approximate stay duration at a GPS sample index.
    # Mirrors the client-side estimateStayAt logic in field_tracking_map_controller.js.
    class StayEstimateCalculator
      MINIMUM_STAY_RADIUS_METERS = 25
      MAXIMUM_STAY_RADIUS_METERS = 60
      MAXIMUM_STAY_SAMPLE_GAP_SECONDS = 300
      MOVING_SPEED_THRESHOLD_MPS = 0.8
      EARTH_RADIUS_METERS = 6_371_000

      Result = Struct.new(:label, :seconds, :radius_meters, keyword_init: true)

      # @param points [Array<ClinicManagement::FieldTrackPoint, Hash>]
      # @param selected_index [Integer]
      # @return [Result]
      def self.call(points, selected_index: 0)
        new(points, selected_index: selected_index).call
      end

      def initialize(points, selected_index: 0)
        @points = Array(points)
        @selected_index = selected_index
      end

      def call
        return empty_result if @points.empty?

        index = @selected_index.clamp(0, @points.size - 1)
        selected = @points[index]
        selected_speed = numeric(selected[:speed_mps] || selected.try(:speed_mps))
        radius_meters = stay_radius_meters(selected)

        if selected_speed && selected_speed > MOVING_SPEED_THRESHOLD_MPS
          return Result.new(label: "Em deslocamento neste registro", seconds: 0, radius_meters: radius_meters)
        end

        start_index = index
        end_index = index

        while start_index.positive? &&
              points_belong_to_stay?(selected, @points[start_index - 1], @points[start_index])
          start_index -= 1
        end

        while end_index < @points.size - 1 &&
              points_belong_to_stay?(selected, @points[end_index + 1], @points[end_index])
          end_index += 1
        end

        started_at = recorded_at(@points[start_index])
        ended_at = recorded_at(@points[end_index])
        seconds = if started_at && ended_at
                      [(ended_at - started_at).to_i, 0].max
                    else
                      0
                    end

        if seconds.zero?
          return Result.new(label: "Não estimável neste ponto", seconds: 0, radius_meters: radius_meters)
        end

        duration_label = seconds < 60 ? "Menos de 1 min" : format_duration(seconds)
        Result.new(
          label: "#{duration_label} no raio de #{radius_meters} m",
          seconds: seconds,
          radius_meters: radius_meters
        )
      end

      private

      def empty_result
        Result.new(label: "Aguardando GPS", seconds: 0, radius_meters: MINIMUM_STAY_RADIUS_METERS)
      end

      def points_belong_to_stay?(anchor, candidate, neighbour)
        candidate_speed = numeric(candidate[:speed_mps] || candidate.try(:speed_mps))
        return false if candidate_speed && candidate_speed > MOVING_SPEED_THRESHOLD_MPS

        candidate_time = recorded_at(candidate)
        neighbour_time = recorded_at(neighbour)
        return false unless candidate_time && neighbour_time

        gap_seconds = (candidate_time - neighbour_time).abs.to_i
        return false if gap_seconds > MAXIMUM_STAY_SAMPLE_GAP_SECONDS

        distance_meters(anchor, candidate) <= stay_radius_meters(anchor)
      end

      def stay_radius_meters(point)
        accuracy = numeric(point[:accuracy_meters] || point.try(:accuracy_meters))
        proposed = accuracy&.positive? ? accuracy * 2 : MINIMUM_STAY_RADIUS_METERS
        [[proposed, MINIMUM_STAY_RADIUS_METERS].max, MAXIMUM_STAY_RADIUS_METERS].min.round
      end

      def recorded_at(point)
        value = point[:recorded_at] || point.try(:recorded_at)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def numeric(value)
        return nil if value.nil?

        number = value.to_f
        number.finite? ? number : nil
      end

      def distance_meters(first, second)
        lat1 = numeric(first[:latitude] || first.try(:latitude)).to_f
        lon1 = numeric(first[:longitude] || first.try(:longitude)).to_f
        lat2 = numeric(second[:latitude] || second.try(:latitude)).to_f
        lon2 = numeric(second[:longitude] || second.try(:longitude)).to_f

        lat1_rad = lat1 * Math::PI / 180
        lat2_rad = lat2 * Math::PI / 180
        dlat = (lat2 - lat1) * Math::PI / 180
        dlon = (lon2 - lon1) * Math::PI / 180

        haversine = Math.sin(dlat / 2)**2 +
                    Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon / 2)**2

        EARTH_RADIUS_METERS * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
      end

      def format_duration(total_seconds)
        minutes = [total_seconds / 60, 1].max.round
        hours = minutes / 60
        remaining_minutes = minutes % 60
        return "#{minutes} min" if hours.zero?
        return "#{hours} h" if remaining_minutes.zero?

        "#{hours} h #{remaining_minutes} min"
      end
    end
  end
end
