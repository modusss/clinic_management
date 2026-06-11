module ClinicManagement
  # ESSENTIAL: Nightly reconciliation for ServiceStatistic — day/month rollover and sales freeze window.
  class DailyServiceStatisticsReconciliationJob < ApplicationJob
    include GoodJob::ActiveJobExtensions::Concurrency

    queue_as :default

    good_job_control_concurrency_with(
      total: 1,
      key: "clinic_daily_service_statistics_reconciliation"
    )

    BATCH_SIZE = 100

    def perform
      refresh_scope(ClinicManagement::Service.where(date: Date.yesterday))

      if ServiceStatistics::Policy.retail_sales_enabled?
        sales_freeze_date = Date.current - 31.days
        refresh_scope(ClinicManagement::Service.where(date: sales_freeze_date))

        refresh_scope(
          ClinicManagement::Service.where(date: Date.current.beginning_of_month...Date.current)
        )
      end

      return unless Date.current.day == 1

      refresh_scope(ClinicManagement::Service.where(date: Date.current.prev_month.all_month))
    end

    private

    def refresh_scope(scope)
      scope.order(:date).find_each(batch_size: BATCH_SIZE) do |service|
        ServiceStatistics::Refresher.call(service)
      end
    end
  end
end
