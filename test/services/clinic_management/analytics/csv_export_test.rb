require "test_helper"
require "csv"

module ClinicManagement
  module Analytics
    class CsvExportTest < ActiveSupport::TestCase
      self.fixture_table_names = []

      test "exports aggregate metrics with spreadsheet formula protection" do
        analytics = {
          patients: 2, attended: 1, exams: 1, sessions: 1,
          sales: 1, sales_amount: 200.to_d, show_sales: true,
          days: [], shifts: [], hours: [],
          regions: [{ label: "=DANGEROUS()", patients: 2, attended: 1,
                      exams: 1, sessions: 1, sales: 1, sales_amount: 200.to_d }]
        }

        result = CsvExport.new(
          analytics, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31)
        ).call
        rows = CSV.parse(result.delete_prefix("\uFEFF"), col_sep: ";")

        assert_equal "Inteligência de Atendimentos", rows.first.first
        assert rows.any? { |row| row.first == "Faturamento atribuído" }
        assert rows.any? { |row| row.first == "'=DANGEROUS()" }
      end
    end
  end
end
