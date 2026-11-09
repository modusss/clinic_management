require "test_helper"

module ClinicManagement
  module Analytics
    class DrilldownTest < ActiveSupport::TestCase
      self.fixture_table_names = []

      setup do
        @drilldown = Drilldown.new(
          start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31),
          service_location_id: nil
        )
      end

      test "rejects invalid dimensions without loading records" do
        assert_nil @drilldown.call(dimension: "orders", value: "all")
        assert_nil @drilldown.call(dimension: "hour", value: "25")
        assert_nil @drilldown.call(dimension: "day_hour", value: "8:16")
        assert_nil @drilldown.call(dimension: "weekday_shift", value: "8:morning")
        assert_nil @drilldown.call(dimension: "weekday_shift", value: "1:dawn")
        assert_nil @drilldown.call(dimension: "weekday_shift", value: "6:morning")
        assert_nil @drilldown.call(dimension: "shift", value: "morning")
        assert_nil @drilldown.call(dimension: "hour", value: "9")
        assert_nil @drilldown.call(dimension: "day_hour", value: "6:9")
        assert_nil @drilldown.call(dimension: "region", value: "x" * 151)
        assert_nil @drilldown.call(dimension: "booking_origin", value: "unknown")
      end

      test "returns an empty paginated detail when the dimension is valid" do
        result = @drilldown.call(dimension: "weekday", value: "1")
        assert_equal 0, result[:total]
        assert_equal 1, result[:pages]
        assert_empty result[:rows]
        booking_result = @drilldown.call(dimension: "booking_origin", value: "same_day")
        assert_equal 0, booking_result[:total]
        assert_equal "Origem: Encaixes no dia", booking_result[:label]
      end
    end
  end
end
