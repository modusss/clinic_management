module ClinicManagement
  module ServiceStatistics
    # ESSENTIAL: Rules for when clinic service metrics are persisted vs read live.
    # Aligns with business reality: remarcados change retroactively; today/current month are open funnels.
    module Policy
      module_function

      # Remarcados can change when a patient reschedules later — never cache this metric.
      # @return [Boolean]
      def rescheduled_always_live?
        true
      end

      # Patient totals and attendance for today and the current calendar month stay live on reads.
      # @param service_date [Date]
      # @return [Boolean]
      def appointment_counts_live?(service_date)
        service_date >= Date.current.beginning_of_month
      end

      # Only closed months (before the current month) get persisted appointment snapshots.
      # @param service_date [Date]
      # @return [Boolean]
      def persist_appointment_counts?(service_date)
        service_date < Date.current.beginning_of_month
      end

      # Sales attribution window closes 30 days after the service date.
      # @param service_date [Date]
      # @return [Boolean]
      def sales_frozen?(service_date)
        service_date + 30.days < Date.current
      end

      # Background job may refresh sales for past services until the window closes.
      # @param service_date [Date]
      # @return [Boolean]
      def refresh_sales?(service_date)
        service_date < Date.current
      end

      # Skip background refresh entirely for today — day is still open.
      # @param service_date [Date]
      # @return [Boolean]
      def refreshable?(service_date)
        service_date < Date.current
      end

      # Global service-level cache applies only when not filtering by captador.
      # @param referral [Referral, nil]
      # @return [Boolean]
      def cache_enabled_for_scope?(referral:)
        referral.nil?
      end
    end
  end
end
