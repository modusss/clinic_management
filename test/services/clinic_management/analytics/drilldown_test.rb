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
        assert_nil @drilldown.call(dimension: "region", value: "x" * 151)
      end

      test "returns an empty paginated detail when the dimension is valid" do
        result = @drilldown.call(dimension: "weekday", value: "1")
        assert_equal 0, result[:total]
        assert_equal 1, result[:pages]
        assert_empty result[:rows]
      end
    end
  end
end
