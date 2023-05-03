require "application_system_test_case"

module ClinicManagement
  class AppointmentsTest < ApplicationSystemTestCase
    setup do
      @appointment = clinic_management_appointments(:one)
    end

    test "visiting the index" do
      visit appointments_url
      assert_selector "h1", text: "Appointments"
    end

    test "should create appointment" do
      visit appointments_url
      click_on "New appointment"

      check "Attendance" if @appointment.attendance
      fill_in "Lead", with: @appointment.lead_id
      fill_in "Service", with: @appointment.service_id
      fill_in "Status", with: @appointment.status
      click_on "Create Appointment"

      assert_text "Appointment was successfully created"
      click_on "Back"
    end

    test "should update Appointment" do
      visit appointment_url(@appointment)
      click_on "Edit this appointment", match: :first

      check "Attendance" if @appointment.attendance
      fill_in "Lead", with: @appointment.lead_id
      fill_in "Service", with: @appointment.service_id
      fill_in "Status", with: @appointment.status
      click_on "Update Appointment"

      assert_text "Appointment was successfully updated"
      click_on "Back"
    end

    test "should destroy Appointment" do
      visit appointment_url(@appointment)
      click_on "Destroy this appointment", match: :first

      assert_text "Appointment was successfully destroyed"
    end
  end
end
