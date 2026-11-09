module ClinicManagement
  # ESSENTIAL: Initial / catch-up population of ServiceStatistic rows (non-blocking).
  class BackfillServiceStatisticsJob < ApplicationJob
    include GoodJob::ActiveJobExtensions::Concurrency

    queue_as :default

    good_job_control_concurrency_with(
      total: 1,
      key: "clinic_backfill_service_statistics"
    )

    BATCH_SIZE = 100

    # @param before_date [String, Date, nil] closed-month cutoff (defaults to beginning of current month)
    # @param refresh_current_month_sales [Boolean] refresh sales snapshots for the open month (through yesterday)
    def perform(before_date = nil, refresh_current_month_sales = true)
      closed_month_cutoff = before_date.present? ? Date.parse(before_date.to_s) : Date.current.beginning_of_month

      closed_services = ClinicManagement::Service.where("date < ?", closed_month_cutoff)
      if ServiceStatistics::Policy.retail_sales_enabled?
        closed_services = closed_services.left_joins(:service_statistic).where(
          "clinic_management_service_statistics.id IS NULL OR clinic_management_service_statistics.sales_metrics_version < ?",
          ServiceStatistics::FinancialMetrics::VERSION
        )
      else
        closed_services = closed_services.where.missing(:service_statistic)
      end

      closed_services.order(:date).find_each(batch_size: BATCH_SIZE) do |service|
          ServiceStatistics::Refresher.call(service)
      end

      if refresh_current_month_sales && ServiceStatistics::Policy.retail_sales_enabled?
        ClinicManagement::Service
          .left_joins(:service_statistic)
          .where(date: Date.current.beginning_of_month...Date.current)
          .where(
            "clinic_management_service_statistics.id IS NULL OR clinic_management_service_statistics.sales_metrics_version < ?",
            ServiceStatistics::FinancialMetrics::VERSION
          )
          .order(:date)
          .find_each(batch_size: BATCH_SIZE) do |service|
            ServiceStatistics::Refresher.call(service)
          end
      end
    ensure
      ServiceStatistics::Bootstrap.clear_enqueue_lock!
    end
  end
end
