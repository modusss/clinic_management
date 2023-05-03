require "application_system_test_case"

module ClinicManagement
  class InvitationsTest < ApplicationSystemTestCase
    setup do
      @invitation = clinic_management_invitations(:one)
    end

    test "visiting the index" do
      visit invitations_url
      assert_selector "h1", text: "Invitations"
    end

    test "should create invitation" do
      visit invitations_url
      click_on "New invitation"

      fill_in "Appointment", with: @invitation.appointment_id
      fill_in "Lead", with: @invitation.lead_id
      fill_in "Notes", with: @invitation.notes
      fill_in "Patient name", with: @invitation.patient_name
      fill_in "Referral", with: @invitation.referral_id
      fill_in "Region", with: @invitation.region_id
      click_on "Create Invitation"

      assert_text "Invitation was successfully created"
      click_on "Back"
    end

    test "should update Invitation" do
      visit invitation_url(@invitation)
      click_on "Edit this invitation", match: :first

      fill_in "Appointment", with: @invitation.appointment_id
      fill_in "Lead", with: @invitation.lead_id
      fill_in "Notes", with: @invitation.notes
      fill_in "Patient name", with: @invitation.patient_name
      fill_in "Referral", with: @invitation.referral_id
      fill_in "Region", with: @invitation.region_id
      click_on "Update Invitation"

      assert_text "Invitation was successfully updated"
      click_on "Back"
    end

    test "should destroy Invitation" do
      visit invitation_url(@invitation)
      click_on "Destroy this invitation", match: :first

      assert_text "Invitation was successfully destroyed"
    end
  end
end
