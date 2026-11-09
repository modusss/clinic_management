require "test_helper"
require "minitest/mock"

module ClinicManagement
  module Analytics
    class SalesAttributionTest < ActiveSupport::TestCase
      self.fixture_table_names = []

      FakeAppointment = Struct.new(:id, :lead_id, :service_id, :present) do
        def attendance?
          present
        end
      end

      FakeRelation = Struct.new(:rows) do
        def where(*)
          self
        end

        def pluck(*)
          rows
        end
      end

      test "assigns an overlapping order only to the most recent attended visit" do
        visits = [FakeAppointment.new(10, 100, 1, true), FakeAppointment.new(20, 100, 2, true)]
        dates = { 1 => Date.new(2026, 9, 2), 2 => Date.new(2026, 9, 12) }
        conversions = FakeRelation.new([[100, 500]])
        orders = FakeRelation.new([[900, 500, Time.zone.local(2026, 9, 14, 15), 300.to_d]])

        LeadsConversion.stub(:where, conversions) do
          Order.stub(:where, orders) do
            result = SalesAttribution.new(appointments: visits, service_dates: dates).call
            assert_empty result.fetch(10, [])
            assert_equal 1, result[20].size
            assert_equal 900, result[20].first[:order_id]
            assert_equal 300.to_d, result[20].first[:amount]
          end
        end
      end

      test "does not query orders if no one attended" do
        result = SalesAttribution.new(
          appointments: [FakeAppointment.new(10, 100, 1, false)],
          service_dates: { 1 => Date.new(2026, 9, 2) }
        ).call
        assert_empty result
      end
    end
  end
end
