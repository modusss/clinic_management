require "test_helper"

module ClinicManagement
  module Analytics
    class BookingOriginTest < ActiveSupport::TestCase
      self.fixture_table_names = []

      FakeInvitation = Struct.new(:patient_name, keyword_init: true)
      FakeAppointment = Struct.new(:id, :lead_id, :service_id, :status, :created_at,
                                   :updated_at, :rescheduled_from_appointment_id,
                                   :invitation, :lead, keyword_init: true)

      setup do
        @exam_date = Date.new(2026, 11, 9)
      end

      test "separates advance bookings, same-day bookings and late entries in the service timezone" do
        advance = booking(1, "2026-11-08 14:00")
        same_day = booking(2, "2026-11-09 14:00")
        # UTC date is the 10th, but the local booking was on the 9th.
        near_midnight = booking(3, "2026-11-10 01:30 UTC")
        later = booking(4, "2026-11-10 14:00")
        classifier = BookingOrigin.new(
          appointments: [advance, same_day, near_midnight, later],
          service_dates: { 5 => @exam_date }, legacy_reschedules: []
        )

        assert_equal :advance, classifier.category(advance, @exam_date)
        assert_equal :same_day, classifier.category(same_day, @exam_date)
        assert_equal :same_day, classifier.category(near_midnight, @exam_date)
        assert_equal :after_date, classifier.category(later, @exam_date)
      end

      test "does not equate attendance updates or slot overbooking with same-day booking" do
        advance = booking(1, "2026-11-08 11:00")
        advance.updated_at = Time.zone.parse("2026-11-09 16:00")
        classifier = BookingOrigin.new(appointments: [advance], service_dates: { 5 => @exam_date }, legacy_reschedules: [])

        assert_equal :advance, classifier.category(advance, @exam_date)
      end

      test "recognizes explicitly linked and carefully matched legacy remarcations" do
        linked = booking(11, "2026-11-09 13:00", previous_id: 8)
        legacy = booking(12, "2026-11-09 14:00", lead_id: 20, patient: "Maria Souza")
        prior = booking(8, "2026-11-04 09:00", lead_id: 20, status: "remarcado", patient: " Maria   Souza ")
        prior.updated_at = Time.zone.parse("2026-11-09 13:59")
        sibling = booking(13, "2026-11-09 14:01", lead_id: 20, patient: "João Souza")
        classifier = BookingOrigin.new(
          appointments: [linked, legacy, sibling],
          service_dates: { 5 => @exam_date }, legacy_reschedules: [prior]
        )

        assert_equal :rescheduled_same_day, classifier.category(linked, @exam_date)
        assert_equal :rescheduled_same_day, classifier.category(legacy, @exam_date)
        assert_equal :same_day, classifier.category(sibling, @exam_date)
      end

      test "does not treat a stale reschedule as a new reschedule and ignores replaced records" do
        current = booking(21, "2026-11-09 14:00", lead_id: 30)
        stale = booking(20, "2026-10-01 10:00", lead_id: 30, status: "remarcado")
        stale.updated_at = Time.zone.parse("2026-10-01 10:30")
        canceled = booking(22, "2026-11-09 15:00", status: "cancelado")
        classifier = BookingOrigin.new(
          appointments: [current, canceled], service_dates: { 5 => @exam_date }, legacy_reschedules: [stale]
        )

        assert_equal :same_day, classifier.category(current, @exam_date)
        assert_nil classifier.category(canceled, @exam_date)
        assert_nil classifier.category(stale, @exam_date)
      end

      private

      def booking(id, time, lead_id: id, status: "agendado", previous_id: nil, patient: "Maria Souza")
        timestamp = Time.zone.parse(time)
        FakeAppointment.new(
          id: id, lead_id: lead_id, service_id: 5, status: status,
          created_at: timestamp, updated_at: timestamp,
          rescheduled_from_appointment_id: previous_id,
          invitation: FakeInvitation.new(patient_name: patient)
        )
      end
    end
  end
end
