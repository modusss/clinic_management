require "test_helper"

module ClinicManagement
  module Analytics
    class ReferralRankingTest < ActiveSupport::TestCase
      self.fixture_table_names = []

      test "sorts captadores by number of markings descending with alphabetic ties" do
        ranking = ReferralRanking.new(
          start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31),
          service_location_id: nil
        )
        referrals = [["Ana", 1], ["Zeca", 2], ["Brenda", 3], ["Local", 4]]
        ranked = ranking.rank(referrals, { 1 => 7, 2 => 12, 3 => 12 })

        assert_equal [3, 2, 1, 4], ranked.map { |row| row[:id] }
        assert_equal [12, 12, 7, 0], ranked.map { |row| row[:count] }
      end
    end
  end
end
