require "test_helper"

module ClinicManagement
  class AppointmentTest < ActiveSupport::TestCase
    test "clears a legacy scheduled time when the service uses arrival order" do
      lead = leads(:one)
      service = services(:one)
      service.update_columns(booking_mode: "arrival_order", interval_minutes: nil, date: Date.current)
      invitation = Invitation.create!(
        lead: lead,
        referral: referrals(:one),
        region: regions(:one),
        patient_name: "Paciente por ordem de chegada"
      )
      appointment = Appointment.new(
        lead: lead,
        service: service,
        invitation: invitation,
        status: "agendado",
        scheduled_at: Time.zone.now.change(sec: 0)
      )

      assert appointment.save, appointment.errors.full_messages.to_sentence
      assert_nil appointment.scheduled_at
    end

    test "rejects duplicate appointment for same service, same patient name and phone" do
      lead = leads(:one)
      lead.update!(name: "Maria da Silva", phone: "77988625125")
      service = services(:one)
      inv1 = invitations(:one)
      inv2 = Invitation.create!(lead: lead, patient_name: lead.name, referral: inv1.referral, region: inv1.region)

      first = Appointment.new(lead: lead, service: service, invitation: inv1, status: "agendado")
      assert first.save, "First appointment should save: #{first.errors.full_messages}"

      second = Appointment.new(lead: lead, service: service, invitation: inv2, status: "agendado")
      assert_not second.save, "Second appointment (same lead, same service) must not save"
      assert_includes second.errors[:base].join, "agendamento"
    end
  end
end
