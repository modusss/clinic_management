require "test_helper"

module ClinicManagement
  class InvitationsControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    setup do
      @invitation = clinic_management_invitations(:one)
    end

    test "should get index" do
      get invitations_url
      assert_response :success
    end

    test "should get new" do
      get new_invitation_url
      assert_response :success
    end

    test "should create invitation" do
      assert_difference("Invitation.count") do
        post invitations_url, params: { invitation: { appointment_id: @invitation.appointment_id, lead_id: @invitation.lead_id, notes: @invitation.notes, patient_name: @invitation.patient_name, referral_id: @invitation.referral_id, region_id: @invitation.region_id } }
      end

      assert_redirected_to invitation_url(Invitation.last)
    end

    test "should show invitation" do
      get invitation_url(@invitation)
      assert_response :success
    end

    test "should get edit" do
      get edit_invitation_url(@invitation)
      assert_response :success
    end

    test "should update invitation" do
      patch invitation_url(@invitation), params: { invitation: { appointment_id: @invitation.appointment_id, lead_id: @invitation.lead_id, notes: @invitation.notes, patient_name: @invitation.patient_name, referral_id: @invitation.referral_id, region_id: @invitation.region_id } }
      assert_redirected_to invitation_url(@invitation)
    end

    test "should destroy invitation" do
      assert_difference("Invitation.count", -1) do
        delete invitation_url(@invitation)
      end

      assert_redirected_to invitations_url
    end
  end
end
