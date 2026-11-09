require "test_helper"

module ClinicManagement
  module Analytics
    class OverviewTest < ActiveSupport::TestCase
      # This isolated analytics test creates no fixtures; unrelated legacy fixture
      # references in the host application have invalid foreign keys.
      self.fixture_table_names = []

      test "returns complete empty comparisons when no services exist" do
        result = Overview.new(
          start_date: Date.new(1900, 1, 1),
          end_date: Date.new(1900, 1, 31),
          service_location_id: nil
        ).call

        assert_equal 0, result[:patients]
        assert_equal 0, result[:attended]
        assert_equal 0, result[:exams]
        assert_equal 0, result[:sessions]
        assert_equal 7, result[:days].size
        assert_equal 3, result[:shifts].size
        assert_equal 24, result[:hours].size
        assert_equal 7, result[:heatmap].size
        assert result[:heatmap].all? { |hours| hours.size == 24 }
        assert_empty result[:regions]
        assert_equal 4, result[:booking_origins].size
        assert_equal 0, result[:same_day_bookings]
        assert_equal 0, result[:advance_bookings]
      end
    end
  end
end
