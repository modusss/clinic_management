require "test_helper"
require "minitest/mock"

module ClinicManagement
  class LeadsControllerBulkLogicTest < ActiveSupport::TestCase
    setup do
      @controller = ClinicManagement::LeadsController.new
    end

    test "bulk_whatsapp_check_outcome returns confirmed_no_whatsapp only when api confirms no whatsapp" do
      outcome = @controller.send(:bulk_whatsapp_check_outcome, { exists: false, error: nil })

      assert_equal :confirmed_no_whatsapp, outcome
    end

    test "bulk_whatsapp_check_outcome returns api_error when verification has error" do
      outcome = @controller.send(:bulk_whatsapp_check_outcome, { exists: false, error: "HTTP 500" })

      assert_equal :api_error, outcome
    end

    test "bulk_whatsapp_check_outcome returns valid_or_unknown when exists is true" do
      outcome = @controller.send(:bulk_whatsapp_check_outcome, { exists: true, error: nil })

      assert_equal :valid_or_unknown, outcome
    end

    test "bulk_whatsapp_check_outcome returns valid_or_unknown when payload is incomplete without error" do
      outcome = @controller.send(:bulk_whatsapp_check_outcome, {})

      assert_equal :valid_or_unknown, outcome
    end

    test "absent patient-type filter reuses latest appointment joined in base query" do
      @controller.params = ActionController::Parameters.new(patient_type: "absent")
      base = ClinicManagement::Lead.joins(
        "INNER JOIN clinic_management_appointments AS main_apt ON main_apt.lead_id = clinic_management_leads.id"
      )

      filtered = @controller.stub(:current_account, nil) do
        @controller.send(:filter_by_patient_type, base)
      end

      assert_includes filtered.to_sql, "main_apt.attendance = FALSE"
      refute_includes filtered.to_sql, "latest_apt"
    end
  end
end
