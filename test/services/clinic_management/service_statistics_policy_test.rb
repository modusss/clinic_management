# frozen_string_literal: true

require "test_helper"

class ClinicManagement::ServiceStatisticsPolicyTest < ActiveSupport::TestCase
  test "remarcados are always live" do
    assert ClinicManagement::ServiceStatistics::Policy.rescheduled_always_live?
  end

  test "appointment counts are live for current month and today" do
    travel_to Date.new(2026, 6, 11) do
      assert ClinicManagement::ServiceStatistics::Policy.appointment_counts_live?(Date.new(2026, 6, 1))
      assert ClinicManagement::ServiceStatistics::Policy.appointment_counts_live?(Date.new(2026, 6, 11))
      assert_not ClinicManagement::ServiceStatistics::Policy.appointment_counts_live?(Date.new(2026, 5, 31))
    end
  end

  test "appointment snapshots persist only for closed months" do
    travel_to Date.new(2026, 6, 11) do
      assert ClinicManagement::ServiceStatistics::Policy.persist_appointment_counts?(Date.new(2026, 5, 31))
      assert_not ClinicManagement::ServiceStatistics::Policy.persist_appointment_counts?(Date.new(2026, 6, 1))
    end
  end

  test "sales freeze after thirty-day attribution window" do
    travel_to Date.new(2026, 6, 11) do
      assert ClinicManagement::ServiceStatistics::Policy.sales_frozen?(Date.new(2026, 5, 10))
      assert_not ClinicManagement::ServiceStatistics::Policy.sales_frozen?(Date.new(2026, 5, 20))
    end
  end

  test "today is not refreshable" do
    travel_to Date.new(2026, 6, 11) do
      assert_not ClinicManagement::ServiceStatistics::Policy.refreshable?(Date.current)
      assert ClinicManagement::ServiceStatistics::Policy.refreshable?(Date.new(2026, 6, 10))
    end
  end
end
