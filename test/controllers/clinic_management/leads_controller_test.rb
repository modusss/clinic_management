require "test_helper"

module ClinicManagement
  class LeadsControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    setup do
      @lead = clinic_management_leads(:one)
    end

    test "should get index" do
      get leads_url
      assert_response :success
    end

    test "should get new" do
      get new_lead_url
      assert_response :success
    end

    test "should create lead" do
      assert_difference("Lead.count") do
        post leads_url, params: { lead: { address: @lead.address, converted: @lead.converted, name: @lead.name, phone: @lead.phone } }
      end

      assert_redirected_to lead_url(Lead.last)
    end

    test "should show lead" do
      get lead_url(@lead)
      assert_response :success
    end

    test "shared reschedule modal retains a service booked by another patient under the lead" do
      lead = Lead.create!(name: "Responsável da família", phone: "77999990000")
      referral = Referral.find_or_create_by!(name: "Local")
      region = Region.ensure_local!
      miguel_service = Service.create!(
        date: Date.current + 1.day,
        weekday: (Date.current + 1.day).wday,
        start_time: "08:00",
        end_time: "12:00"
      )
      jose_service = Service.create!(
        date: Date.current + 2.days,
        weekday: (Date.current + 2.days).wday,
        start_time: "13:00",
        end_time: "17:00"
      )
      miguel_invitation = Invitation.create!(
        lead: lead,
        referral: referral,
        region: region,
        patient_name: "Miguel"
      )
      jose_invitation = Invitation.create!(
        lead: lead,
        referral: referral,
        region: region,
        patient_name: "José"
      )
      Appointment.create!(lead: lead, service: miguel_service, invitation: miguel_invitation, status: "agendado")
      Appointment.create!(lead: lead, service: jose_service, invitation: jose_invitation, status: "agendado")

      get lead_url(lead)

      assert_response :success
      assert_select "#reschedule-slot-modal .reschedule-slot-service-option[data-service-id='#{jose_service.id}']", minimum: 1
    end

    test "should get edit" do
      get edit_lead_url(@lead)
      assert_response :success
    end

    test "should update lead" do
      patch lead_url(@lead), params: { lead: { address: @lead.address, converted: @lead.converted, name: @lead.name, phone: @lead.phone } }
      assert_redirected_to lead_url(@lead)
    end

    test "should destroy lead" do
      assert_difference("Lead.count", -1) do
        delete lead_url(@lead)
      end

      assert_redirected_to leads_url
    end
  end
end
