module ClinicManagement
  module ServiceStatistics
    # Computes and persists ServiceStatistic rows (excluding remarcados).
    class Refresher
      # ESSENTIAL: Paid statuses must stay aligned with Order#total_paid_amount in the host app.
      PAID_PAYMENT_STATUSES = %w[PAYMENT_RECEIVED RECEIVED CONFIRMED RECEIVED_IN_CASH PAID].freeze

      # @param service [ClinicManagement::Service]
      # @return [ClinicManagement::ServiceStatistic, nil]
      def self.call(service)
        new(service).call
      end

      # @param service [ClinicManagement::Service]
      def initialize(service)
        @service = service
      end

      # @return [ClinicManagement::ServiceStatistic, nil]
      def call
        return nil unless Policy.refreshable?(@service.date)

        statistic = ClinicManagement::ServiceStatistic.find_or_initialize_by(service: @service)
        statistic.service_date = @service.date
        statistic.service_location_id = @service.service_location_id
        now = Time.current

        if Policy.persist_appointment_counts?(@service.date)
          patients, attended, canceled = appointment_counts
          statistic.patients_count = patients
          statistic.attended_count = attended
          statistic.canceled_count = canceled
          statistic.appointment_counts_computed_at = now
        end

        if Policy.persist_sales?(@service.date)
          metrics = sales_metrics
          statistic.sales_customers_count = metrics[:sales_customers_count]
          statistic.sales_amount = metrics[:sales_amount]
          statistic.receipts_amount = metrics[:receipts_amount]
          statistic.sales_computed_at = now
          statistic.sales_frozen_at = now if Policy.sales_frozen?(@service.date)
        end

        statistic.save!
        statistic
      end

      # Live sales metrics for one service (used by Reader fallback paths).
      # @return [Hash]
      def sales_metrics
        {
          sales_customers_count: sales_count,
          sales_amount: sales_amount,
          receipts_amount: receipts_amount
        }
      end

      # Enqueues refresh for services that may attribute sales to a customer order.
      # @param customer_id [Integer]
      def self.enqueue_for_customer(customer_id)
        return if customer_id.blank?
        return unless Policy.retail_sales_enabled?

        lead_ids = ClinicManagement::Conversion.where(customers_id: customer_id).pluck(:lead_id)
        return if lead_ids.empty?

        service_ids = ClinicManagement::Appointment
                        .where(lead_id: lead_ids, attendance: true)
                        .joins(:service)
                        .merge(ClinicManagement::Service.where(date: (Date.current - 60.days)..Date.current))
                        .distinct
                        .pluck(:service_id)

        service_ids.each do |service_id|
          ClinicManagement::RefreshServiceStatisticsJob.perform_later(service_id)
        end
      end

      private

      def appointments
        @appointments ||= @service.appointments.to_a
      end

      def appointment_counts
        total = appointments.size
        attended = appointments.count { |row| row.attendance == true }
        canceled = appointments.count { |row| row.status == "cancelado" }
        [total, attended, canceled]
      end

      def attended_customer_ids
        appointments
          .select { |row| row.attendance == true }
          .filter_map { |row| row.lead&.leads_conversion&.customer_id }
      end

      def service_orders_scope
        customer_ids = attended_customer_ids
        return Order.none if customer_ids.empty?

        Order.where(customer_id: customer_ids)
             .where(created_at: @service.date.beginning_of_day..(@service.date + 30.days).end_of_day)
      end

      def sales_amount
        service_orders_scope.sum(:total_amount)
      end

      def sales_count
        service_orders_scope.distinct.count(:customer_id)
      end

      def receipts_amount
        order_ids = service_orders_scope.pluck(:id)
        return 0 if order_ids.empty?

        early_total = EarlyPayment.where(order_id: order_ids, status: PAID_PAYMENT_STATUSES).sum(:amount)
        pickup_total = PickupPayment.where(order_id: order_ids, status: PAID_PAYMENT_STATUSES).sum(:amount)
        installments_total = Installment.joins(:payment_book)
                                        .where(payment_books: { order_id: order_ids })
                                        .where(installments: { status: PAID_PAYMENT_STATUSES })
                                        .sum("installments.amount")

        early_total + pickup_total + installments_total
      end
    end
  end
end
