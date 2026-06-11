module ClinicManagement
  # ESSENTIAL: Backfill / maintenance for ServiceStatistic rows.
  class BackfillServiceStatisticsJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 100

    # @param before_date [String, Date, nil] closed-month cutoff (defaults to beginning of current month)
    # @param refresh_current_month_sales [Boolean] refresh sales snapshots for the open month (through yesterday)
    def perform(before_date = nil, refresh_current_month_sales = true)
      closed_month_cutoff = before_date.present? ? Date.parse(before_date.to_s) : Date.current.beginning_of_month

      ClinicManagement::Service
        .where("date < ?", closed_month_cutoff)
        .order(:date)
        .find_each(batch_size: BATCH_SIZE) do |service|
          ServiceStatistics::Refresher.call(service)
        end

      return unless refresh_current_month_sales

      ClinicManagement::Service
        .where(date: Date.current.beginning_of_month...Date.current)
        .order(:date)
        .find_each(batch_size: BATCH_SIZE) do |service|
          ServiceStatistics::Refresher.call(service)
        end
    end
  end
end
