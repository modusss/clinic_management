require "test_helper"

module ClinicManagement
  class TimeSlotsHelperTest < ActiveSupport::TestCase
    include ClinicManagement::TimeSlotsHelper

    setup do
      @location = ServiceLocation.create!(name: "Agenda por tipo #{SecureRandom.hex(4)}")
      @first_type = ServiceType.create!(name: "Tipo A #{SecureRandom.hex(4)}")
      @second_type = ServiceType.create!(name: "Tipo B #{SecureRandom.hex(4)}")
      @third_type = ServiceType.create!(name: "Tipo C #{SecureRandom.hex(4)}")
      @date = Date.current + 1.day
      weekday = @date.wday == 6 ? 7 : @date.wday + 1
      @slot = TimeSlot.create!(
        weekday: weekday,
        start_time: "06:10",
        end_time: "07:10",
        service_location: @location
      )
      Service.create!(
        date: @date,
        weekday: weekday,
        start_time: @slot.start_time,
        end_time: @slot.end_time,
        service_location: @location,
        service_type: @first_type
      )
    end

    test "an occupied range remains available for another service type" do
      first_type_keys = available_keys(@first_type)
      second_type_keys = available_keys(@second_type)
      expected_key = [@date, @slot.start_time.strftime("%H:%M")]

      assert_not_includes first_type_keys, expected_key
      assert_includes second_type_keys, expected_key
    end

    test "a range restricted to selected service types is hidden from the others" do
      @slot.update!(all_service_types: false, service_type_ids: [@second_type.id])
      expected_key = [@date, @slot.start_time.strftime("%H:%M")]

      assert_includes available_keys(@second_type), expected_key
      assert_not_includes available_keys(@third_type), expected_key
    end

    private

    def current_service_location_id
      @location.id.to_s
    end

    def available_keys(service_type)
      available_time_slots_for_next_30_days(service_type_id: service_type.id)
        .map { |item| [item[:date], item[:time_slot].start_time.strftime("%H:%M")] }
    end
  end
end
