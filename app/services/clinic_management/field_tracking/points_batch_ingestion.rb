# frozen_string_literal: true

require "set"

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
        seen_client_point_ids = Set.new
        normalized_points = @points.filter_map { |raw| normalize_point(raw) }
        existing_client_point_ids = load_existing_client_point_ids(
          normalized_points.map { |point| point[:client_point_id] }
        )

        normalized_points.each do |attrs|
          client_point_id = attrs[:client_point_id]

          if seen_client_point_ids.include?(client_point_id) || existing_client_point_ids.include?(client_point_id)
            skipped += 1
            next
          end

          begin
            @shift.field_track_points.create!(attrs)
            created += 1
            seen_client_point_ids.add(client_point_id)
            existing_client_point_ids.add(client_point_id)
          rescue ActiveRecord::RecordNotUnique
            # ESSENTIAL: Mobile retries can race past the pre-check — unique index is the final guard.
            skipped += 1
            existing_client_point_ids.add(client_point_id)
          end
        end

        if created.positive?
          @shift.increment!(:points_count, created)
          # ESSENTIAL: Keep active-shift metrics fresh without blocking the mobile batch response.
          ClinicManagement::FieldTracking::ShiftMetricsRefreshJob.perform_later(@shift.id)
        end

        { created: created, skipped: skipped, points_count: @shift.reload.points_count }
      end

      private

      def load_existing_client_point_ids(client_point_ids)
        ids = client_point_ids.compact.uniq
        return Set.new if ids.empty?

        @shift.field_track_points.where(client_point_id: ids).pluck(:client_point_id).to_set
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
