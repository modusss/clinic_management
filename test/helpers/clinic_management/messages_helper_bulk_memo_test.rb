# frozen_string_literal: true

require "test_helper"

module ClinicManagement
  class MessagesHelperBulkMemoTest < ActiveSupport::TestCase
    test "repeated Meta permission checks reuse one phone resolution per request" do
      helper = Object.new.extend(ClinicManagement::MessagesHelper)
      account = Object.new
      account.define_singleton_method(:meta_whatsapp_enabled?) { true }
      phone = Object.new
      phone.define_singleton_method(:can_send_message?) { true }
      calls = 0

      helper.define_singleton_method(:current_account) { account }
      helper.define_singleton_method(:current_user) { Object.new }
      helper.define_singleton_method(:meta_bulk_absent_role_allowed?) { true }
      helper.define_singleton_method(:meta_bulk_account_operational?) { true }
      helper.define_singleton_method(:bulk_meta_phone_for_absent) { calls += 1; phone }

      50.times { assert helper.can_use_meta_bulk_for_absent? }
      assert_equal 1, calls
    end
  end
end
