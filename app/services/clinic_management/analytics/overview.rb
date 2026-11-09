module ClinicManagement
  module Analytics
    # Aggregates historical appointment activity for an at-most-one-year window.
    # ESSENTIAL: Prescription#created_at is the examination time, per clinic workflow;
    # it is not an arrival timestamp. Keep undated prescriptions out of hourly rankings.
    class Overview
      WEEKDAYS = %w[Segunda Terça Quarta Quinta Sexta Sábado Domingo].freeze

      def initialize(start_date:, end_date:, service_location_id:, include_sales: false, region_id: nil, referral_id: nil)
        @start_date = start_date
        @end_date = end_date
        @service_location_id = service_location_id
        @include_sales = include_sales && ServiceStatistics::Policy.retail_sales_enabled?
        @region_id = region_id
        @referral_id = referral_id
      end

      def call
        services = Service.for_location(@service_location_id)
                          .where(date: @start_date..@end_date, canceled: [false, nil])
        service_dates = services.pluck(:id, :date)
        service_day = service_dates.to_h
        # ESSENTIAL: Attribute orders across all visits in the location/date scope
        # BEFORE filtering by region or captador. Otherwise an order could be
        # reassigned to an older visit when its newer visit is hidden by a filter.
        all_appointments = Appointment.where(service_id: service_day.keys)
                                      .includes(:prescription, invitation: :region).to_a
        sales_by_appointment = @include_sales ? SalesAttribution.new(appointments: all_appointments, service_dates: service_day).call : {}
        appointments = all_appointments.select do |appointment|
          invitation = appointment.invitation
          (!@region_id || invitation&.region_id == @region_id) &&
            (!@referral_id || invitation&.referral_id == @referral_id)
        end
        if @region_id || @referral_id
          selected_service_ids = appointments.map(&:service_id).to_set
          service_dates.select! { |service_id, _| selected_service_ids.include?(service_id) }
          service_day = service_dates.to_h
        end

        days = Array.new(7) { |index| blank_group(WEEKDAYS[index]) }
        shifts = %w[Manhã Tarde Noite].index_with { |name| blank_group(name) }
        hours = (0..23).index_with { |hour| blank_group(format('%02d:00', hour)) }
        heatmap = Array.new(7) { Array.new(24, 0) }
        regions = {}
        examined = 0
        attended = 0
        sales_total = 0.to_d
        order_ids = Set.new
        buyer_ids = Set.new

        appointments.each do |appointment|
          service_date = service_day[appointment.service_id]
          next unless service_date

          day = days[service_date.cwday - 1]
          increment_patient(day, appointment)
          region_name = appointment.invitation&.region&.name.presence || 'Sem região'
          region = (regions[region_name] ||= blank_group(region_name))
          increment_patient(region, appointment)
          attended += 1 if appointment.attendance?

          appointment_sales = sales_by_appointment.fetch(appointment.id, [])
          apply_sales(day, appointment_sales)
          apply_sales(region, appointment_sales)
          appointment_sales.each do |sale|
            sales_total += sale[:amount]
            order_ids << sale[:order_id]
            buyer_ids << sale[:customer_id]
          end

          prescription = appointment.prescription
          next unless prescription

          examined += 1
          day[:exams] += 1
          region[:exams] += 1
          # An entered-on-another-day prescription cannot reliably identify the exam hour.
          created = prescription.created_at&.in_time_zone
          next unless created&.to_date == service_date

          hour = created.hour
          shift = shifts[hour < 12 ? 'Manhã' : hour < 18 ? 'Tarde' : 'Noite']
          shift[:exams] += 1
          hours[hour][:exams] += 1
          heatmap[service_date.cwday - 1][hour] += 1
          apply_sales(shift, appointment_sales)
          apply_sales(hours[hour], appointment_sales)
        end

        service_dates.each do |_, date|
          days[date.cwday - 1][:sessions] += 1
        end

        all_groups = days + shifts.values + hours.values + regions.values
        all_groups.each { |group| finalize_sales(group) }

        {
          patients: appointments.size, attended: attended, exams: examined,
          sales: buyer_ids.size, orders: order_ids.size, sales_amount: sales_total,
          show_sales: @include_sales,
          sessions: service_dates.size, days: days, shifts: shifts.values,
          hours: hours.values, heatmap: heatmap,
          regions: regions.values.sort_by { |row| [-row[:attended], row[:label]] }
        }
      end

      private

      def blank_group(label)
        { label: label, patients: 0, attended: 0, exams: 0, sessions: 0,
          sales_amount: 0.to_d, buyers: Set.new, orders: Set.new }
      end

      def increment_patient(group, appointment)
        group[:patients] += 1
        group[:attended] += 1 if appointment.attendance?
      end

      # Attach each order once per group; multiple orders from a buyer count as one buyer.
      def apply_sales(group, sales)
        sales.each do |sale|
          next unless group[:orders].add?(sale[:order_id])

          group[:buyers] << sale[:customer_id]
          group[:sales_amount] += sale[:amount]
        end
      end

      def finalize_sales(group)
        group[:sales] = group.delete(:buyers).size
        group.delete(:orders)
      end
    end
  end
end
