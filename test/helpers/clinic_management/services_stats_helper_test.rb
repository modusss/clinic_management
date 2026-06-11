# frozen_string_literal: true

require "test_helper"

class ClinicManagement::ServicesStatsHelperTest < ActionView::TestCase
  include ClinicManagement::ServicesStatsHelper

  test "services_conversion_rate returns zero when denominator is zero" do
    assert_equal 0.0, services_conversion_rate(5, 0)
  end

  test "services_conversion_rate calculates percentage with one decimal" do
    assert_equal 52.6, services_conversion_rate(41, 78)
    assert_equal 14.7, services_conversion_rate(41, 279)
  end

  test "services_attendance_rate_tone follows funnel thresholds" do
    assert_equal "red", services_attendance_rate_tone(28.0)
    assert_equal "orange", services_attendance_rate_tone(34.4)
    assert_equal "green", services_attendance_rate_tone(56.8)
  end

  test "services_final_rate_tone uses lower compound funnel thresholds" do
    assert_equal "red", services_final_rate_tone(8.0)
    assert_equal "orange", services_final_rate_tone(14.7)
    assert_equal "green", services_final_rate_tone(24.7)
  end
end
