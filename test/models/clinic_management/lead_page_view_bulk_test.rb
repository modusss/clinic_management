# frozen_string_literal: true

require "test_helper"

module ClinicManagement
  class LeadPageViewBulkTest < ActiveSupport::TestCase
    self.fixture_table_names = []

    setup do
      @user = User.create!(name: "Bulk view test", email: "bulk_view_#{SecureRandom.hex(5)}@example.test",
        password: "password123", password_confirmation: "password123")
      @other = User.create!(name: "Other viewer", email: "other_view_#{SecureRandom.hex(5)}@example.test",
        password: "password123", password_confirmation: "password123")
      @first = ClinicManagement::Lead.create!(name: "Paciente A", phone: "77999991234")
      @second = ClinicManagement::Lead.create!(name: "Paciente B", phone: "77999995678")
    end

    test "bulk registration creates missing rows, refreshes existing rows and preserves other users" do
      old_time = 12.hours.ago
      current = ClinicManagement::LeadPageView.create!(
        lead: @first, user: @user, page_context: "absent",
        viewed_at: old_time, expires_at: old_time + 1.hour
      )
      other = ClinicManagement::LeadPageView.create!(
        lead: @first, user: @other, page_context: "absent",
        viewed_at: old_time, expires_at: 2.hours.from_now
      )

      assert_difference("ClinicManagement::LeadPageView.count", 1) do
        ClinicManagement::LeadPageView.register_views(
          [@first.id, @second.id, @second.id], @user.id, context: "absent", duration_hours: 8
        )
      end

      assert_equal current.created_at, current.reload.created_at
      assert_in_delta 8.hours, current.expires_at - Time.current, 5.seconds
      assert_equal old_time.to_i, other.reload.viewed_at.to_i
      assert_equal 1, ClinicManagement::LeadPageView.where(lead: @second, user: @user, page_context: "absent").count
      assert_includes ClinicManagement::LeadPageView.blocked_lead_ids_for_user(@user.id), @first.id
    end

    test "empty batch does not touch any rows" do
      assert_no_difference("ClinicManagement::LeadPageView.count") do
        ClinicManagement::LeadPageView.register_views([], @user.id)
      end
    end

    test "batch registration uses constant database round trips for 50 patients" do
      ids = [@first.id, @second.id] +
        48.times.map do |i|
          ClinicManagement::Lead.create!(name: "Paciente extra #{i}", phone: "77#{(9_900_0000 + i).to_s.rjust(9, '0')}").id
        end
      sql = []
      observer = lambda do |*args|
        payload = args.last
        sql << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached]
      end
      ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
        ClinicManagement::LeadPageView.register_views(ids, @user.id, context: "absent", duration_hours: 8)
      end

      assert_operator sql.size, :<=, 4, "Expected bulk operations, not one query per patient: #{sql.size}"
      assert_equal 50, ClinicManagement::LeadPageView.where(user: @user, page_context: "absent").count
    end
  end
end
