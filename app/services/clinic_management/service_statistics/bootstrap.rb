module ClinicManagement
  module ServiceStatistics
    # ESSENTIAL: One-time bootstrap when aggregated stats view is opened and snapshots are missing.
    # Enqueues BackfillServiceStatisticsJob once; after populate, required? stays false.
    module Bootstrap
      ENQUEUE_LOCK_KEY = "clinic_management/service_statistics/backfill_enqueued"

      module_function

      # @return [Boolean] true when closed-month services lack ServiceStatistic rows (or current-month sales rows in retail mode)
      def required?
        closed_month_services_missing_snapshot? || current_month_sales_snapshots_missing?
      end

      # Enqueues backfill at most once until the job completes (Redis unless_exist lock).
      # @return [Boolean] true when a new job was enqueued
      def enqueue_once!
        return false unless required?

        lock_acquired = Rails.cache.write(
          ENQUEUE_LOCK_KEY,
          Time.current.to_i,
          expires_in: 2.hours,
          unless_exist: true
        )
        return false unless lock_acquired

        ClinicManagement::BackfillServiceStatisticsJob.perform_later
        true
      end

      # @return [void]
      def clear_enqueue_lock!
        Rails.cache.delete(ENQUEUE_LOCK_KEY)
      end

      # @return [Boolean]
      def backfill_pending?
        Rails.cache.exist?(ENQUEUE_LOCK_KEY)
      end

      # @return [Boolean]
      def closed_month_services_missing_snapshot?
        ClinicManagement::Service
          .where("date < ?", Date.current.beginning_of_month)
          .where.missing(:service_statistic)
          .exists?
      end

      # @return [Boolean]
      def current_month_sales_snapshots_missing?
        return false unless Policy.retail_sales_enabled?

        ClinicManagement::Service
          .where(date: Date.current.beginning_of_month...Date.current)
          .where.missing(:service_statistic)
          .exists?
      end
    end
  end
end
