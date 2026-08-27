# frozen_string_literal: true

require "test_helper"

module ClinicManagement
  module Lpvoz
    class AvailabilitySlotsTest < Minitest::Test
      FakeLocation = Struct.new(:name)
      FakeService = Struct.new(:id, :date, :service_location, :available_appointment_times)

      def test_returns_only_future_slots_and_keeps_representative_options_from_each_day
        now = Time.zone.local(2026, 8, 26, 14, 15)
        first_day = FakeService.new(
          10,
          Date.new(2026, 8, 26),
          FakeLocation.new("Interno"),
          [
            Time.zone.local(2026, 8, 26, 13, 0),
            Time.zone.local(2026, 8, 26, 14, 0),
            Time.zone.local(2026, 8, 26, 14, 30),
            Time.zone.local(2026, 8, 26, 15, 0),
            Time.zone.local(2026, 8, 26, 15, 30),
            Time.zone.local(2026, 8, 26, 16, 0)
          ]
        )
        second_day = FakeService.new(
          11,
          Date.new(2026, 8, 27),
          FakeLocation.new("Interno"),
          [
            Time.zone.local(2026, 8, 27, 9, 0),
            Time.zone.local(2026, 8, 27, 9, 30)
          ]
        )

        slots = AvailabilitySlots.new(
          services: [first_day, second_day],
          now:
        ).call

        assert_equal 5, slots.size
        assert_equal [
          "2026-08-26T14:30:00Z",
          "2026-08-26T15:00:00Z",
          "2026-08-26T15:30:00Z",
          "2026-08-27T09:00:00Z",
          "2026-08-27T09:30:00Z"
        ], slots.pluck(:scheduled_at)
        assert_equal ["10", "10", "10", "11", "11"], slots.pluck(:service_id)
      end

      def test_shares_the_daily_limit_across_multiple_services_on_the_same_date
        now = Time.zone.local(2026, 8, 26, 8, 0)
        services = [
          FakeService.new(
            20,
            Date.new(2026, 8, 28),
            nil,
            [
              Time.zone.local(2026, 8, 28, 9, 0),
              Time.zone.local(2026, 8, 28, 9, 30)
            ]
          ),
          FakeService.new(
            21,
            Date.new(2026, 8, 28),
            nil,
            [
              Time.zone.local(2026, 8, 28, 10, 0),
              Time.zone.local(2026, 8, 28, 10, 30)
            ]
          )
        ]

        slots = AvailabilitySlots.new(services:, now:).call

        assert_equal 3, slots.size
        assert_equal ["20", "20", "21"], slots.pluck(:service_id)
      end

      def test_keeps_an_afternoon_option_when_morning_service_is_processed_first
        now = Time.zone.local(2026, 8, 26, 8, 0)
        services = [
          FakeService.new(
            30,
            Date.new(2026, 8, 28),
            FakeLocation.new("Interno"),
            [
              Time.zone.local(2026, 8, 28, 9, 0),
              Time.zone.local(2026, 8, 28, 9, 30),
              Time.zone.local(2026, 8, 28, 10, 0)
            ]
          ),
          FakeService.new(
            31,
            Date.new(2026, 8, 28),
            FakeLocation.new("Interno"),
            [
              Time.zone.local(2026, 8, 28, 13, 0),
              Time.zone.local(2026, 8, 28, 13, 30)
            ]
          )
        ]

        slots = AvailabilitySlots.new(services:, now:).call

        assert_equal 3, slots.size
        assert_equal ["09:00", "09:30", "13:00"], slots.map { |slot| Time.zone.parse(slot[:scheduled_at]).strftime("%H:%M") }
        assert_equal ["30", "30", "31"], slots.pluck(:service_id)
      end
    end
  end
end
