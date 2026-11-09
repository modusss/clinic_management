require "test_helper"

module ClinicManagement
  class AnalyticsAccessTest < ActiveSupport::TestCase
    self.fixture_table_names = []

    FakeMemberships = Struct.new(:rows) do
      def where(account:, role:)
        matches = rows.any? { |row| row[:account] == account && role.include?(row[:role]) }
        Struct.new(:exists?).new(matches)
      end
    end

    test "only manager and owner memberships in the current account can view analytics" do
      current_account = Object.new
      other_account = Object.new

      assert_access(true, current_account, [{ account: current_account, role: "manager" }])
      assert_access(true, current_account, [{ account: current_account, role: "owner" }])
      assert_access(false, current_account, [{ account: current_account, role: "operator" }])
      assert_access(false, current_account, [{ account: current_account, role: "basic" }])
      assert_access(false, current_account, [{ account: other_account, role: "owner" }])
      assert_access(true, current_account, [
        { account: other_account, role: "owner" },
        { account: current_account, role: "manager" }
      ])
    end

    private

    def assert_access(expected, account, rows)
      user = Struct.new(:memberships).new(FakeMemberships.new(rows))
      controller = ApplicationController.new
      controller.define_singleton_method(:current_user) { user }
      controller.define_singleton_method(:current_account) { account }
      assert_equal expected, controller.send(:analytics_access_allowed?)
    end
  end
end
