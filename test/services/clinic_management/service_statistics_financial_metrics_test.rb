# frozen_string_literal: true

require "test_helper"

module ClinicManagement
  class ServiceStatisticsFinancialMetricsTest < ActiveSupport::TestCase
    self.fixture_table_names = []
    include ActiveJob::TestHelper

    setup do
      @customer_id = insert(Customer, name: "Paciente teste financeiro")
      @lead_id = insert(ClinicManagement::Lead, name: "Lead teste financeiro")
      insert(LeadsConversion, customer_id: @customer_id, clinic_management_lead_id: @lead_id)
      @first = session_on(Date.new(2026, 9, 2))
      @second = session_on(Date.new(2026, 9, 12))
    end

    test "assigns orders to a single attended session and includes later payments" do
      first_order = order_on(Date.new(2026, 9, 4), amount: 1000)
      second_order = order_on(Date.new(2026, 9, 15), amount: 500)
      insert(EarlyPayment, order_id: first_order, amount: 300, status: "RECEIVED",
                           paid_at: Time.zone.local(2026, 9, 4, 15))
      insert(PickupPayment, order_id: first_order, amount: 500, status: "RECEIVED",
                            paid_at: Time.zone.local(2026, 9, 20, 15))

      receipt = insert(Cashflow, flow_type: "in", amount: 500, date: Date.new(2026, 9, 20))
      refund = insert(Cashflow, flow_type: "out", amount: 100, date: Date.new(2026, 9, 22),
                                original_cashflow_id: receipt)
      insert(CashflowOrder, cashflow_id: receipt, order_id: first_order)
      insert(CashflowOrder, cashflow_id: refund, order_id: first_order)

      first_metrics = report(@first)
      assert_equal 1, first_metrics[:sales_customers_count]
      assert_equal 1000.to_d, first_metrics[:sales_amount]
      assert_equal 700.to_d, first_metrics[:receipts_amount]
      assert_equal 300.to_d, first_metrics[:pending_amount]

      second_metrics = report(@second)
      assert_equal 1, second_metrics[:sales_customers_count]
      assert_equal 500.to_d, second_metrics[:sales_amount]
      assert_equal 0.to_d, second_metrics[:receipts_amount]
      assert_equal 500.to_d, second_metrics[:pending_amount]
    end

    test "does not count canceled orders and uses actual manual installment amount" do
      active_order = order_on(Date.new(2026, 9, 4), amount: 600)
      order_on(Date.new(2026, 9, 5), amount: 200, canceled: true)
      book = insert(PaymentBook, order_id: active_order)
      insert(Installment, payment_book_id: book, amount: 400, paid_amount: 350,
                          status: "RECEIVED_IN_CASH", payment_date: Date.new(2026, 9, 25))

      metrics = report(@first)
      assert_equal 1, metrics[:sales_customers_count]
      assert_equal 600.to_d, metrics[:sales_amount]
      assert_equal 350.to_d, metrics[:receipts_amount]
      assert_equal 250.to_d, metrics[:pending_amount]
    end

    test "a later received payment schedules a refresh of the original exam" do
      order_id = order_on(Date.new(2026, 9, 4), amount: 600)
      payment_id = insert(EarlyPayment, order_id: order_id, amount: 200, status: "PENDING")
      clear_enqueued_jobs

      assert_enqueued_with(job: ClinicManagement::RefreshServiceStatisticsJob,
                           args: [@first.id]) do
        EarlyPayment.find(payment_id).update!(status: "RECEIVED",
                                              paid_at: Time.zone.local(2026, 10, 25, 10))
      end
    end

    test "attributes a later payment to the actual hour of the original exam" do
      appointment_id = @first.appointments.first.id
      insert(ClinicManagement::Prescription, appointment_id: appointment_id,
             created_at: Time.zone.local(2026, 9, 2, 11, 50))
      order_id = order_on(Date.new(2026, 9, 4), amount: 900)
      insert(EarlyPayment, order_id: order_id, amount: 200, status: "RECEIVED")
      insert(PickupPayment, order_id: order_id, amount: 500, status: "RECEIVED",
                            paid_at: Time.zone.local(2026, 10, 30, 15))

      metrics = report(@first)
      assert_equal 900.to_d, metrics[:sales_amount]
      assert_equal 700.to_d, metrics[:receipts_amount]
      assert_equal({ sales_amount: 900.to_d, receipts_amount: 700.to_d },
                   metrics[:financial_by_exam_shift]["morning"])
      assert_nil metrics[:financial_by_exam_shift]["afternoon"]

      ClinicManagement::ServiceStatistics::Refresher.call(@first)
      snapshot = ClinicManagement::ServiceStatistic.find_by!(service_id: @first.id)
      assert_equal ClinicManagement::ServiceStatistics::FinancialMetrics::VERSION, snapshot.sales_metrics_version
      assert_equal "900.0", snapshot.financial_by_exam_shift.dig("morning", "sales_amount")
      assert_equal "700.0", snapshot.financial_by_exam_shift.dig("morning", "receipts_amount")
    end

    private

    def report(service)
      ClinicManagement::ServiceStatistics::FinancialMetrics.new(service: service).call
    end

    def session_on(date)
      service = ClinicManagement::Service.find(insert(ClinicManagement::Service, date: date))
      insert(ClinicManagement::Appointment, lead_id: @lead_id, service_id: service.id,
                                             attendance: true)
      service
    end

    def order_on(date, amount:, canceled: false)
      insert(Order, customer_id: @customer_id, total_amount: amount, canceled: canceled,
                    os: "FIN-#{SecureRandom.hex(8)}",
                    delivery_date: date + 7.days,
                    created_at: Time.zone.local(date.year, date.month, date.day, 15))
    end

    def insert(model, attributes)
      now = Time.current
      model.insert_all!([{ created_at: now, updated_at: now }.merge(attributes)]).rows.first.first
    end
  end
end
