require "test_helper"
require "csv"

module ClinicManagement
  module Analytics
    class CsvExportTest < ActiveSupport::TestCase
      self.fixture_table_names = []

      test "exports aggregate metrics with spreadsheet formula protection" do
        analytics = {
          patients: 2, attended: 1, exams: 1, sessions: 1,
          advance_bookings: 1, same_day_bookings: 1, rescheduled_same_day_bookings: 0,
          day_shifts: [{ label: "Sábado · Manhã", exams: 30, weekday: 6, shift: "morning" }],
          booking_origins: [{ label: "Encaixes no dia", patients: 1, attended: 1, exams: 1, sales: 1, sales_amount: 200.to_d }],
          sales: 1, sales_amount: 200.to_d, show_sales: true,
          days: [], shifts: [], hours: [],
          regions: [{ label: "=DANGEROUS()", patients: 2, attended: 1,
                      exams: 1, sessions: 1, sales: 1, sales_amount: 200.to_d }],
          customer_geography: {
            customers: 1, with_district: 1, without_district: 0,
            districts: [{ label: "=BAIRRO()", customers: 1, appointments: 2, attended: 1, exams: 1, sales: 1, sales_amount: 200.to_d }],
            crossings: [{ origin: "=ORIGEM()", label: "=BAIRRO()", customers: 1, appointments: 2, attended: 1, exams: 1, sales: 1, sales_amount: 200.to_d }]
          }
        }

        result = CsvExport.new(
          analytics, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31)
        ).call
        rows = CSV.parse(result.delete_prefix("\uFEFF"), col_sep: ";")

        assert_equal "Inteligência de Atendimentos", rows.first.first
        assert rows.any? { |row| row.first == "Faturamento atribuído" }
        assert rows.any? { |row| row.first == "Encaixes do dia ativos" && row[1] == "1" }
        assert rows.any? { |row| row.first == "Origem das marcações (fichas ativas)" }
        assert rows.any? { |row| row.first == "Encaixes no dia" && row[1] == "1" }
        assert rows.any? { |row| row.first == "Ranking de dias e turnos" }
        assert rows.any? { |row| row.first == "Sábado · Manhã" && row[1] == "30" }
        assert rows.any? { |row| row.first == "'=DANGEROUS()" }
        assert rows.any? { |row| row.first == "Bairros dos clientes" }
        assert rows.any? { |row| row.first == "'=BAIRRO()" }
        assert rows.any? { |row| row.first == "'=ORIGEM()" && row[1] == "'=BAIRRO()" }
      end
    end
  end
end
