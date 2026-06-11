module ClinicManagement
  module ServiceStatistics
    # Resolves per-service metrics mixing cached ServiceStatistic rows with live queries.
    class Reader
      EMPTY_TOTALS = {
        appointments: 0,
        scheduled: 0,
        rescheduled: 0,
        canceled: 0,
        sales: 0,
        sales_amount: 0,
        receipts_amount: 0
      }.freeze

      attr_reader :include_sales

      # @param referral [Referral, nil] captador filter — disables cache when present
      # @param include_sales [Boolean]
      def initialize(referral: nil, include_sales: false)
        @referral = referral
        @include_sales = include_sales
        @cache_enabled = Policy.cache_enabled_for_scope?(referral: referral)
        @statistics_by_service_id = {}
        @prepared = false
      end

      # ESSENTIAL: Preload statistic rows once per request before iterating many service buckets.
      # @param services [Enumerable<ClinicManagement::Service>]
      # @return [void]
      def prepare!(services)
        @statistics_by_service_id = preload_statistics(services.to_a)
        @prepared = true
      end

      # @param services [Enumerable<ClinicManagement::Service>]
      # @return [Hash]
      def totals_for(services)
        prepare!(services) unless @prepared
        totals_for_services(services)
      end

      # @param services [Enumerable<ClinicManagement::Service>]
      # @return [Hash]
      def totals_for_services(services)
        service_list = services.to_a
        return EMPTY_TOTALS.dup if service_list.empty?

        service_list.each_with_object(EMPTY_TOTALS.dup) do |service, totals|
          metrics = metrics_for(service, @statistics_by_service_id[service.id])
          totals.each_key { |key| totals[key] += metrics[key] }
        end
      end

      private

      def preload_statistics(services)
        return {} unless @cache_enabled

        service_ids = services.map(&:id)
        return {} if service_ids.empty?

        ClinicManagement::ServiceStatistic.where(service_id: service_ids).index_by(&:service_id)
      end

      def metrics_for(service, statistic)
        appointments = filtered_appointments(service)
        rescheduled = appointments.count { |row| row.status == "remarcado" }

        patients, attended, canceled = resolve_appointment_counts(service, appointments, statistic)
        sales, sales_amount, receipts_amount = resolve_sales_metrics(service, statistic)

        {
          appointments: patients,
          scheduled: attended,
          rescheduled: rescheduled,
          canceled: canceled,
          sales: sales,
          sales_amount: sales_amount,
          receipts_amount: receipts_amount
        }
      end

      def filtered_appointments(service)
        rows = service.appointments.to_a
        return rows if @referral.nil?

        rows.select { |row| row.invitation&.referral == @referral }
      end

      def resolve_appointment_counts(service, appointments, statistic)
        if live_appointment_counts?(service)
          [
            appointments.size,
            appointments.count { |row| row.attendance == true },
            appointments.count { |row| row.status == "cancelado" }
          ]
        elsif statistic.present?
          [statistic.patients_count, statistic.attended_count, statistic.canceled_count]
        else
          [
            appointments.size,
            appointments.count { |row| row.attendance == true },
            appointments.count { |row| row.status == "cancelado" }
          ]
        end
      end

      def resolve_sales_metrics(service, statistic)
        return [0, 0, 0] unless @include_sales

        if cached_sales?(service, statistic)
          [statistic.sales_customers_count, statistic.sales_amount, statistic.receipts_amount]
        else
          live_sales_metrics(service)
        end
      end

      def live_appointment_counts?(service)
        !@cache_enabled || Policy.appointment_counts_live?(service.date)
      end

      # ESSENTIAL: Prefer persisted snapshot (kept fresh by jobs) over per-request Order queries.
      # Fully frozen rows are never recomputed on read; open-window rows use last job snapshot.
      def cached_sales?(service, statistic)
        return false unless @cache_enabled && statistic.present?

        if Policy.sales_frozen?(service.date)
          statistic.sales_frozen_at.present?
        else
          statistic.sales_computed_at.present?
        end
      end

      def live_sales_metrics(service)
        metrics = Refresher.new(service).sales_metrics
        [
          metrics[:sales_customers_count],
          metrics[:sales_amount],
          metrics[:receipts_amount]
        ]
      end
    end
  end
end
