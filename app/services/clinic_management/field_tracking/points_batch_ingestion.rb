# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Ingests up to 100 GPS points idempotently for an active shift.
    class PointsBatchIngestion
      MAX_BATCH_SIZE = 100

      class Error < StandardError
        attr_reader :code

        def initialize(code, message = code)
          @code = code
          super(message)
        end
      end

      # @param shift [ClinicManagement::FieldShift]
      # @param points [Array<Hash>]
      # @return [Hash] :created, :skipped, :points_count
      def self.call(shift:, points:)
        new(shift: shift, points: points).call
      end

      def initialize(shift:, points:)
        @shift = shift
        @points = Array(points)
      end

      def call
        raise Error.new("shift_not_active") unless @shift.active?
        raise Error.new("batch_too_large") if @points.size > MAX_BATCH_SIZE

        created = 0
        skipped = 0

        @points.each do |raw|
          attrs = normalize_point(raw)
          next if attrs.nil?

          if duplicate?(attrs[:client_point_id])
            skipped += 1
            next
          end

          @shift.field_track_points.create!(attrs)
          created += 1
        end

        if created.positive?
          @shift.increment!(:points_count, created)
        end

        { created: created, skipped: skipped, points_count: @shift.reload.points_count }
      end

      private

      def duplicate?(client_point_id)
        @shift.field_track_points.exists?(client_point_id: client_point_id)
      end

      def normalize_point(raw)
        h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        h = h.stringify_keys

        client_point_id = h["client_point_id"].presence
        recorded_at = parse_time(h["recorded_at"])
        latitude = h["latitude"]
        longitude = h["longitude"]
        return nil if client_point_id.blank? || recorded_at.nil? || latitude.blank? || longitude.blank?

        {
          client_point_id: client_point_id,
          recorded_at: recorded_at,
          latitude: latitude,
          longitude: longitude,
          accuracy_meters: h["accuracy_meters"],
          speed_mps: h["speed_mps"],
          bearing: h["bearing"]
        }
      end

      def parse_time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
