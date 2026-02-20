require "test_helper"

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
  end
end
