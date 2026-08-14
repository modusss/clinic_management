require "test_helper"

# Host app defines this helper; the engine dummy may not. Stub only when missing so
# ClinicManagement::ApplicationHelper can be included in isolation.
unless defined?(ReferralDisplayLabelsHelper)
  module ReferralDisplayLabelsHelper
  end
end

module ClinicManagement
  class ApplicationHelperTest < ActiveSupport::TestCase
    include ApplicationHelper

    setup do
      @_multiple_active_service_types = nil
      ServiceType.where(removed: false).update_all(removed: true)
    end

    test "multiple_active_service_types? is false when only one type is active" do
      ServiceType.create!(name: "Único #{SecureRandom.hex(4)}")
      reset_service_type_memo!

      assert_not multiple_active_service_types?
    end

    test "multiple_active_service_types? is true when two types are active" do
      ServiceType.create!(name: "Gratuito #{SecureRandom.hex(4)}")
      ServiceType.create!(name: "Oftalmo #{SecureRandom.hex(4)}")
      reset_service_type_memo!

      assert multiple_active_service_types?
    end

    test "slot_modal_service_type_name is omitted when only one type is active" do
      type = ServiceType.create!(name: "Único #{SecureRandom.hex(4)}")
      reset_service_type_memo!
      service = Service.new(service_type: type)

      assert_nil slot_modal_service_type_name(service)
    end

    test "slot_modal_service_type_name returns the type when two types are active" do
      ServiceType.create!(name: "Gratuito #{SecureRandom.hex(4)}")
      oftalmo = ServiceType.create!(name: "Oftalmo #{SecureRandom.hex(4)}")
      reset_service_type_memo!
      service = Service.new(service_type: oftalmo)

      assert_equal oftalmo.name, slot_modal_service_type_name(service)
    end

    test "slot_modal_service_type_name ignores soft-deleted extra types" do
      type = ServiceType.create!(name: "Ativo #{SecureRandom.hex(4)}")
      ServiceType.create!(name: "Removido #{SecureRandom.hex(4)}", removed: true)
      reset_service_type_memo!
      service = Service.new(service_type: type)

      assert_not multiple_active_service_types?
      assert_nil slot_modal_service_type_name(service)
    end

    private

    # Clears the per-request memo after setup mutates ServiceType rows.
    def reset_service_type_memo!
      @_multiple_active_service_types = nil
    end

    # ApplicationHelper#display_service_name reads this; keep a stub for isolation.
    def current_service_location_id
      nil
    end
  end
end
