# frozen_string_literal: true

require "test_helper"

module ClinicManagement
  class DuplicatePatientCheckerTest < ActiveSupport::TestCase
    setup do
      @service = Service.create!(
        date: Date.current + 1.day,
        weekday: (Date.current + 1.day).wday,
        start_time: "08:00",
        end_time: "12:00"
      )
      @lead = Lead.create!(name: "Responsável", phone: "77999999991")
      @region = Region.ensure_local!
      @referral = Referral.find_or_create_by!(name: "Local")
    end

    test "detects a matching first name and returns every patient under the phone" do
      create_appointment("Maria do Carmo")
      create_appointment("Ana Clara")

      result = DuplicatePatientChecker.call(
        service: @service,
        phone: "77999999991",
        patient_name: "Maria da Silva"
      )

      assert_predicate result, :duplicate?
      assert_equal ["Maria do Carmo", "Ana Clara"], result.patients.pluck(:patient_name)
      assert_equal true, result.patients.first[:same_first_name]
      assert_equal false, result.patients.second[:same_first_name]
    end

    test "returns patients for the phone before a patient name has been entered" do
      create_appointment("Maria do Carmo")
      create_appointment("Ana Clara")

      result = DuplicatePatientChecker.call(
        service: @service,
        phone: "(77) 99999-9991",
        patient_name: ""
      )

      assert_not_predicate result, :duplicate?
      assert_equal ["Maria do Carmo", "Ana Clara"], result.patients.pluck(:patient_name)
      assert result.patients.none? { |patient| patient[:same_first_name] }
    end

    test "ignores canceled appointments and appointments in another service" do
      canceled = create_appointment("Maria do Carmo", status: "cancelado")
      other_service = Service.create!(
        date: Date.current + 2.days,
        weekday: (Date.current + 2.days).wday,
        start_time: "13:00",
        end_time: "17:00"
      )
      create_appointment("Maria Alves", service: other_service)

      result = DuplicatePatientChecker.call(
        service: @service,
        phone: @lead.phone,
        patient_name: "Maria"
      )

      assert_not_predicate result, :duplicate?
      assert_equal [], result.patients
      assert_equal "cancelado", canceled.status
    end

    private

    def create_appointment(patient_name, service: @service, status: "agendado")
      invitation = Invitation.create!(
        lead: @lead,
        referral: @referral,
        region: @region,
        patient_name: patient_name
      )
      Appointment.create!(lead: @lead, service: service, invitation: invitation, status: status)
    end
  end
end
