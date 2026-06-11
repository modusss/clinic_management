module ClinicManagement
  module ServiceStatistics
    # Builds period rows and chart payloads in one pass (single stats preload per request).
    class Rollup
      # @param referral [Referral, nil]
      # @param include_sales [Boolean]
      def initialize(referral: nil, include_sales: false)
        @reader = Reader.new(referral: referral, include_sales: include_sales)
      end

      # @param services [Enumerable<ClinicManagement::Service>]
      # @param period [Symbol] :monthly or :weekly
      # @return [Array<Hash>]
      def period_rows(services, period)
        service_list = services.to_a
        return [] if service_list.empty?

        @reader.prepare!(service_list)

        grouper = period == :weekly ? ->(row) { row.date.beginning_of_week } : ->(row) { row.date.beginning_of_month }
        label_builder = period_label_builder(period)

        service_list
          .group_by(&grouper)
          .sort_by { |period_start, _| period_start }
          .reverse
          .map do |period_start, period_services|
            metrics = @reader.totals_for_services(period_services)
            {
              period_label: label_builder.call(period_start),
              services_count: period_services.count,
              patients: metrics[:appointments],
              attended: metrics[:scheduled],
              rescheduled: metrics[:rescheduled],
              canceled: metrics[:canceled],
              sales: metrics[:sales],
              sales_amount: metrics[:sales_amount],
              receipts_amount: metrics[:receipts_amount],
              show_sales: @reader.include_sales
            }
          end
      end

      # @param period_rows [Array<Hash>]
      # @param include_sales [Boolean]
      # @return [Hash] Chart.js-compatible structure
      def chart_data(period_rows, include_sales: false)
        chronological_rows = period_rows.reverse

        labels = chronological_rows.map { |row| row[:period_label] }
        appointments_data = chronological_rows.map { |row| row[:patients] }
        scheduled_data = chronological_rows.map { |row| row[:attended] }
        rescheduled_data = chronological_rows.map { |row| row[:rescheduled] }
        canceled_data = chronological_rows.map { |row| row[:canceled] }
        sales_data = chronological_rows.map { |row| row[:sales] }

        datasets = [
          chart_dataset("Total de Pacientes", appointments_data, "59, 130, 246"),
          chart_dataset("Compareceram", scheduled_data, "34, 197, 94")
        ]

        datasets << chart_dataset("Vendas", sales_data, "147, 51, 234") if include_sales

        datasets += [
          chart_dataset("Remarcados", rescheduled_data, "251, 191, 36"),
          chart_dataset("Cancelados", canceled_data, "239, 68, 68")
        ]

        { labels: labels, datasets: datasets }
      end

      private

      def period_label_builder(period)
        if period == :weekly
          ->(start_date) { "#{start_date.strftime('%d/%m/%Y')} - #{start_date.end_of_week.strftime('%d/%m/%Y')}" }
        else
          ->(start_date) { I18n.l(start_date, format: "%B de %Y").capitalize }
        end
      end

      def chart_dataset(label, data, rgb)
        {
          label: label,
          data: data,
          backgroundColor: "rgba(#{rgb}, 0.5)",
          borderColor: "rgb(#{rgb})",
          borderWidth: 2
        }
      end
    end
  end
end
