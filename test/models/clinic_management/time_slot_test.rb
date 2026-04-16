require "test_helper"

module ClinicManagement
  class TimeSlotTest < ActiveSupport::TestCase
    test "rejects save when start_time is missing" do
      slot = TimeSlot.new(weekday: 2, end_time: "10:00", start_time: nil)
      assert_not slot.valid?
      assert_predicate slot.errors[:start_time], :any?
    end

    test "rejects save when end_time is missing" do
      slot = TimeSlot.new(weekday: 2, start_time: "09:00", end_time: nil)
      assert_not slot.valid?
      assert_predicate slot.errors[:end_time], :any?
    end

    test "rejects save when weekday is missing" do
      slot = TimeSlot.new(weekday: nil, start_time: "09:00", end_time: "10:00")
      assert_not slot.valid?
      assert_predicate slot.errors[:weekday], :any?
    end

    test "rejects save when end_time is before start_time" do
      slot = TimeSlot.new(weekday: 1, start_time: "12:00", end_time: "08:00")
      assert_not slot.valid?
      assert_predicate slot.errors[:end_time], :any?
    end

    test "delete_invalid_time_slots! removes rows with nil times" do
      bad = TimeSlot.new(weekday: 1, start_time: nil, end_time: nil)
      bad.save(validate: false)
      assert TimeSlot.exists?(bad.id)

      TimeSlot.delete_invalid_time_slots!

      assert_not TimeSlot.exists?(bad.id)
    end

    test "delete_invalid_time_slots! removes rows with nil weekday" do
      bad = TimeSlot.new(weekday: nil, start_time: "09:00", end_time: "10:00")
      bad.save(validate: false)
      assert TimeSlot.exists?(bad.id)

      TimeSlot.delete_invalid_time_slots!

      assert_not TimeSlot.exists?(bad.id)
    end
  end
end
