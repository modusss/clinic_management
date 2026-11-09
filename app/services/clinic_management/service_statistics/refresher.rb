module ClinicManagement
  module ServiceStatistics
    # Computes and persists ServiceStatistic rows (excluding remarcados).
    class Refresher
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
          statistic.sales_metrics_version = FinancialMetrics::VERSION
          statistic.sales_frozen_at = now if Policy.sales_frozen?(@service.date)
        end

        statistic.save!
        statistic
      end

      # Live sales metrics for one service (used by Reader fallback paths).
      # @return [Hash]
      def sales_metrics
        FinancialMetrics.new(service: @service).call
      end

      # Payments made at pickup (or months later) must refresh the *original*
      # examination cohort. Restrict candidates by the order date rather than by
      # today's date, otherwise old but still-open orders retain stale receipts.
      def self.enqueue_for_order(order_id)
        return if order_id.blank? || !Policy.retail_sales_enabled?

        order = Order.find_by(id: order_id)
        return unless order

        lead_ids = LeadsConversion.where(customer_id: order.customer_id).pluck(:clinic_management_lead_id)
        return if lead_ids.empty?

        order_date = order.created_at.in_time_zone.to_date
        service_ids = ClinicManagement::Appointment
                        .joins(:service)
                        .where(lead_id: lead_ids, attendance: true)
                        .where(clinic_management_services: {
                          date: (order_date - Analytics::SalesAttribution::WINDOW_DAYS.days)..order_date
                        })
                        .distinct.pluck(:service_id)

        service_ids.each { |service_id| ClinicManagement::RefreshServiceStatisticsJob.perform_later(service_id) }
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

    end
  end
end
