require "test_helper"
require "minitest/mock"

module ClinicManagement
  module Analytics
    class CustomerGeographyTest < ActiveSupport::TestCase
      self.fixture_table_names = []

      FakeAppointment = Struct.new(:id, :lead_id, :invitation, :prescription, :present, keyword_init: true) do
        def attendance?
          present
        end
      end

      test "groups linked customer districts independently from invitation regions" do
        customer = Struct.new(:id, :district).new(42, "  Alto   Maron ")
        conversions = [Struct.new(:clinic_management_lead_id, :customer).new(7, customer)]
        relation = Object.new
        relation.define_singleton_method(:where) { |_conditions| conversions }
        region = Struct.new(:name).new("Candeias")
        invitation = Struct.new(:region).new(region)
        appointments = [
          FakeAppointment.new(id: 1, lead_id: 7, invitation: invitation, prescription: Object.new, present: true),
          FakeAppointment.new(id: 2, lead_id: 7, invitation: invitation, prescription: Object.new, present: true)
        ]
        sales = { 1 => [{ order_id: 10, customer_id: 42, amount: 100.to_d }],
                  2 => [{ order_id: 10, customer_id: 42, amount: 100.to_d }] }

        LeadsConversion.stub(:includes, relation) do
          result = CustomerGeography.new(appointments: appointments, sales_by_appointment: sales, include_sales: true).call
          assert_equal 1, result[:customers]
          assert_equal 1, result[:with_district]
          district = result[:districts].first
          assert_equal "Alto Maron", district[:label]
          assert_equal 1, district[:customers]
          assert_equal 2, district[:appointments]
          assert_equal 2, district[:exams]
          assert_equal 1, district[:sales]
          assert_equal 100.to_d, district[:sales_amount]
          assert_equal "Candeias", result[:crossings].first[:origin]
        end
      end

      test "preserves customers with an unfilled district" do
        customer = Struct.new(:id, :district).new(50, nil)
        conversions = [Struct.new(:clinic_management_lead_id, :customer).new(9, customer)]
        relation = Object.new
        relation.define_singleton_method(:where) { |_conditions| conversions }
        appointment = FakeAppointment.new(id: 3, lead_id: 9, invitation: nil, prescription: nil, present: false)

        LeadsConversion.stub(:includes, relation) do
          result = CustomerGeography.new(appointments: [appointment], sales_by_appointment: {}, include_sales: true).call
          assert_equal 1, result[:without_district]
          assert_equal "Bairro não informado", result[:districts].first[:label]
          assert_equal "Sem região", result[:crossings].first[:origin]
        end
      end
    end
  end
end
