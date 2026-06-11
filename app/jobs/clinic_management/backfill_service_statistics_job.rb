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

      ClinicManagement::Service
        .where("date < ?", closed_month_cutoff)
        .where.missing(:service_statistic)
        .order(:date)
        .find_each(batch_size: BATCH_SIZE) do |service|
          ServiceStatistics::Refresher.call(service)
        end

      if refresh_current_month_sales && ServiceStatistics::Policy.retail_sales_enabled?
        ClinicManagement::Service
          .where(date: Date.current.beginning_of_month...Date.current)
          .where.missing(:service_statistic)
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
