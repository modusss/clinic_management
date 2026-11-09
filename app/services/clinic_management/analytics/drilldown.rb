module ClinicManagement
  module Analytics
    # Provides a bounded, read-only explanation of one aggregate chart cell.
    # ESSENTIAL: Order attribution is calculated on all eligible visits before
    # applying region/referral filters, matching Overview's reconciliation rule.
    class Drilldown
      PAGE_SIZE = 20
      DIMENSIONS = %w[weekday shift hour day_hour region].freeze
      SHIFT_NAMES = { "morning" => "Manhã", "afternoon" => "Tarde", "night" => "Noite" }.freeze

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

        matching = appointments.filter_map do |appointment|
          date = service_dates[appointment.service_id]
          invitation = appointment.invitation
          next unless date && (!@region_id || invitation&.region_id == @region_id)
          next if @referral_id && invitation&.referral_id != @referral_id

          prescription_time = appointment.prescription&.created_at&.in_time_zone
          exam_time = prescription_time if prescription_time&.to_date == date
          next unless matches?(dimension, value, date, exam_time, invitation)

          {
            id: appointment.id, service_id: appointment.service_id,
            date: date, time: exam_time, patient: invitation&.patient_name.presence || appointment.lead&.name.presence || "Paciente sem nome",
            region: invitation&.region&.name.presence || "Sem região",
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
        when "hour" then (0..23).cover?(Integer(value, exception: false)) rescue false
        when "day_hour" then value.match?(/\A[1-7]:(?:[01]?\d|2[0-3])\z/)
        when "shift" then SHIFT_NAMES.key?(value)
        when "region" then value.present? && value.length <= 150
        end
      end

      def matches?(dimension, value, date, exam_time, invitation)
        case dimension
        when "weekday" then date.cwday == value.to_i
        when "hour" then exam_time && exam_time.hour == value.to_i
        when "day_hour"
          weekday, hour = value.split(":").map(&:to_i)
          date.cwday == weekday && exam_time && exam_time.hour == hour
        when "shift"
          exam_time && shift_for(exam_time.hour) == value
        when "region" then (invitation&.region&.name.presence || "Sem região") == value
        end
      end

      def shift_for(hour)
        hour < 12 ? "morning" : hour < 18 ? "afternoon" : "night"
      end

      def dimension_label(dimension, value)
        case dimension
        when "weekday"
          name = Overview::WEEKDAYS[value.to_i - 1]
          value.to_i <= 5 ? "#{name}-feira" : name
        when "hour" then "Exames entre #{format('%02d', value.to_i)}h e #{format('%02d', (value.to_i + 1) % 24)}h"
        when "day_hour"
          weekday, hour = value.split(":").map(&:to_i)
          "#{Overview::WEEKDAYS[weekday - 1]} · #{format('%02d:00', hour)}"
        when "shift" then "Exames no turno: #{SHIFT_NAMES[value]}"
        when "region" then "Pacientes da região: #{value}"
        end
      end
    end
  end
end
