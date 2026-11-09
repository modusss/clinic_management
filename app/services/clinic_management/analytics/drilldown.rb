module ClinicManagement
  module Analytics
    # Provides a bounded, read-only explanation of selected non-time aggregate indicators.
    # Time-based rankings and heatmap cells are summary-only to avoid expensive patient lists.
    # ESSENTIAL: Order attribution is calculated on all eligible visits before
    # applying region/referral filters, matching Overview's reconciliation rule.
    class Drilldown
      PAGE_SIZE = 20
      DIMENSIONS = %w[weekday region booking_origin].freeze

      def initialize(start_date:, end_date:, service_location_id:, region_id: nil, referral_id: nil, include_sales: false)
        @start_date = start_date
        @end_date = end_date
        @service_location_id = service_location_id
        @region_id = region_id
        @referral_id = referral_id
        @include_sales = include_sales && ServiceStatistics::Policy.retail_sales_enabled?
      end

      def call(dimension:, value:, page: nil)
        dimension = dimension.to_s
        value = value.to_s
        return nil unless valid_dimension?(dimension, value)

        service_dates = Service.for_location(@service_location_id)
                               .where(date: @start_date..@end_date, canceled: [false, nil])
                               .pluck(:id, :date).to_h
        appointments = Appointment.where(service_id: service_dates.keys)
                                  .includes(:prescription, :lead, invitation: :region).to_a
        sales_by_appointment = @include_sales ? SalesAttribution.new(appointments: appointments, service_dates: service_dates).call : {}
        visible_appointments = appointments.select do |appointment|
          invitation = appointment.invitation
          (!@region_id || invitation&.region_id == @region_id) &&
            (!@referral_id || invitation&.referral_id == @referral_id)
        end
        origin_classifier = BookingOrigin.new(appointments: visible_appointments, service_dates: service_dates)

        matching = visible_appointments.filter_map do |appointment|
          date = service_dates[appointment.service_id]
          invitation = appointment.invitation
          next unless date

          prescription_time = appointment.prescription&.created_at&.in_time_zone
          exam_time = prescription_time if prescription_time&.to_date == date
          origin = origin_classifier.category(appointment, date)
          next unless matches?(dimension, value, date, exam_time, invitation, origin)

          {
            id: appointment.id, service_id: appointment.service_id,
            date: date, time: exam_time, patient: invitation&.patient_name.presence || appointment.lead&.name.presence || "Paciente sem nome",
            region: invitation&.region&.name.presence || "Sem região",
            booked_at: appointment.created_at&.in_time_zone,
            booking_origin: BookingOrigin::LABELS[origin] || "Remarcado / cancelado",
            attended: appointment.attendance?, exam: appointment.prescription.present?,
            sales_amount: sales_by_appointment.fetch(appointment.id, []).sum { |sale| sale[:amount] }
          }
        end

        matching.sort_by! { |row| [-row[:date].jd, -(row[:time]&.to_i || 0), -row[:id]] }
        current_page = [[Integer(page, exception: false).to_i, 1].max, 10_000].min
        total = matching.size
        {
          label: dimension_label(dimension, value), dimension: dimension, value: value,
          total: total, page: current_page, pages: [(total.to_f / PAGE_SIZE).ceil, 1].max,
          show_sales: @include_sales,
          rows: matching.slice((current_page - 1) * PAGE_SIZE, PAGE_SIZE) || []
        }
      end

      private

      def valid_dimension?(dimension, value)
        return false unless DIMENSIONS.include?(dimension)

        case dimension
        when "weekday" then (1..7).cover?(Integer(value, exception: false)) rescue false
        when "region" then value.present? && value.length <= 150
        when "booking_origin" then BookingOrigin::LABELS.keys.any? { |key| key.to_s == value }
        end
      end

      def matches?(dimension, value, date, exam_time, invitation, origin)
        case dimension
        when "weekday" then date.cwday == value.to_i
        when "region" then (invitation&.region&.name.presence || "Sem região") == value
        when "booking_origin" then origin == value.to_sym
        end
      end

      def dimension_label(dimension, value)
        case dimension
        when "weekday"
          name = Overview::WEEKDAYS[value.to_i - 1]
          value.to_i <= 5 ? "#{name}-feira" : name
        when "region" then "Pacientes da região: #{value}"
        when "booking_origin" then "Origem: #{BookingOrigin::LABELS.fetch(value.to_sym)}"
        end
      end
    end
  end
end
