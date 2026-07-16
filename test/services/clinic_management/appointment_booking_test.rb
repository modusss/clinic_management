require "test_helper"

module ClinicManagement
  class AppointmentBookingTest < ActiveSupport::TestCase
    setup do
      @service = Service.create!(
        date: Date.current + 1.day,
        weekday: 5,
        start_time: "08:00",
        end_time: "09:00",
        booking_mode: "scheduled",
        interval_minutes: 20
      )
      @lead = Lead.create!(name: "Responsável", phone: "15999999999")
      @region = Region.create!(name: "Teste agendamento #{SecureRandom.hex(4)}")
      @referral = Referral.create!(name: "Teste agendamento #{SecureRandom.hex(4)}", phone: "15999999999")
    end

    test "generates starts without including the closing time" do
      assert_equal %w[08:00 08:20 08:40], @service.appointment_times.map { |time| time.strftime("%H:%M") }
    end

    test "self-booking rejects an occupied time" do
      time = @service.appointment_times.first
      AppointmentBooking.new(service: @service).create_consecutive!(
        appointment_attributes: [appointment_attributes("Primeiro paciente")],
        starting_at: time
      )

      assert_raises(AppointmentBooking::UnavailableTime) do
        AppointmentBooking.new(service: @service).create_consecutive!(
          appointment_attributes: [appointment_attributes("Segundo paciente")],
          starting_at: time
        )
      end
    end

    test "authenticated overbooking is marked explicitly" do
      time = @service.appointment_times.first
      AppointmentBooking.new(service: @service).create_consecutive!(
        appointment_attributes: [appointment_attributes("Primeiro paciente")],
        starting_at: time
      )

      appointment = AppointmentBooking.new(service: @service, allow_overbooking: true).create_consecutive!(
        appointment_attributes: [appointment_attributes("Encaixe")],
        starting_at: time
      ).first

      assert_predicate appointment, :overbooked?
      assert_equal time.change(sec: 0), appointment.scheduled_at.change(sec: 0)
    end

    private

    def appointment_attributes(patient_name)
      invitation = Invitation.create!(
        lead: @lead,
        region: @region,
        referral: @referral,
        patient_name: patient_name
      )
      {
        lead: @lead,
        invitation: invitation,
        status: "agendado",
        referral_code: @referral.code,
        self_booked: true
      }
    end
  end
end
