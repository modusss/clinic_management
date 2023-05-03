require "application_system_test_case"

module ClinicManagement
  class ServicesTest < ApplicationSystemTestCase
    setup do
      @service = clinic_management_services(:one)
    end

    test "visiting the index" do
      visit services_url
      assert_selector "h1", text: "Services"
    end

    test "should create service" do
      visit services_url
      click_on "New service"

      fill_in "Date", with: @service.date
      fill_in "End time", with: @service.end_time
      fill_in "Start time", with: @service.start_time
      fill_in "Time slot", with: @service.time_slot_id
      fill_in "Weekday", with: @service.weekday
      click_on "Create Service"

      assert_text "Service was successfully created"
      click_on "Back"
    end

    test "should update Service" do
      visit service_url(@service)
      click_on "Edit this service", match: :first

      fill_in "Date", with: @service.date
      fill_in "End time", with: @service.end_time
      fill_in "Start time", with: @service.start_time
      fill_in "Time slot", with: @service.time_slot_id
      fill_in "Weekday", with: @service.weekday
      click_on "Update Service"

      assert_text "Service was successfully updated"
      click_on "Back"
    end

    test "should destroy Service" do
      visit service_url(@service)
      click_on "Destroy this service", match: :first

      assert_text "Service was successfully destroyed"
    end
  end
end
