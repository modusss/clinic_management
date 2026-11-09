module ClinicManagement
  module Analytics
    # Aggregates historical appointment activity for an at-most-one-year window.
    # ESSENTIAL: Prescription#created_at is the examination time, per clinic workflow;
    # it is not an arrival timestamp. Keep undated prescriptions out of hourly rankings.
    class Overview
      WEEKDAYS = %w[Segunda Terça Quarta Quinta Sexta Sábado Domingo].freeze
      SHIFT_RANGES = [["Manhã", "morning", 0...12], ["Tarde", "afternoon", 12...18], ["Noite", "night", 18...24]].freeze

      def initialize(start_date:, end_date:, service_location_id:, include_sales: false, include_shift_financials: false, region_id: nil, referral_id: nil)
        @start_date = start_date
        @end_date = end_date
        @service_location_id = service_location_id
        @include_sales = include_sales && ServiceStatistics::Policy.retail_sales_enabled?
        # The additional receipt/average analysis is expensive and must only run
        # after an explicit Turbo request (or a requested CSV export).
        @include_shift_financials = @include_sales && include_shift_financials
        @region_id = region_id
        @referral_id = referral_id
      end

      def call
        services = Service.for_location(@service_location_id)
                          .where(date: @start_date..@end_date, canceled: [false, nil])
        service_rows = if @include_shift_financials
          services.pluck(:id, :date, :start_time, :end_time)
        else
          services.pluck(:id, :date).map { |id, date| [id, date, nil, nil] }
        end
        service_dates = service_rows.map { |id, date, _, _| [id, date] }
        service_day = service_dates.to_h
        # ESSENTIAL: Attribute orders across all visits in the location/date scope
        # BEFORE filtering by region or captador. Otherwise an order could be
        # reassigned to an older visit when its newer visit is hidden by a filter.
        all_appointments = Appointment.where(service_id: service_day.keys)
                                      .includes(:prescription, invitation: :region).to_a
        sales_by_appointment = if @include_shift_financials
          attributed_sales(all_appointments, service_day)
        elsif @include_sales
          # Preserve the original, scoped analytics cost during ordinary page
          # loads; extended cross-visit attribution runs only on demand.
          SalesAttribution.new(appointments: all_appointments, service_dates: service_day).call
        else
          {}
        end
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
        booking_origin = BookingOrigin.new(appointments: appointments, service_dates: service_day)
        cached_shift_financials = @include_shift_financials ? shift_financial_snapshots(service_day) : {}
        receipts_by_order = if @include_shift_financials
          uncached_orders = appointments.reject { |appointment| cached_shift_financials.key?(appointment.service_id) }
                                  .flat_map { |appointment| sales_by_appointment.fetch(appointment.id, []).map { |sale| sale[:order_id] } }
          ServiceStatistics::ReceiptsByOrder.call(uncached_orders)
        else
          {}
        end
        shift_financials = Hash.new { |hash, key| hash[key] = { sales_amount: 0.to_d, receipts_amount: 0.to_d } }
        shift_occurrences = Hash.new { |hash, key| hash[key] = Set.new }
        service_rows.each do |service_id, date, start_time, end_time|
          next unless @include_shift_financials
          next unless service_day.key?(service_id) && date <= Date.current && start_time

          start_minute = start_time.hour * 60 + start_time.min
          end_minute = end_time ? end_time.hour * 60 + end_time.min : start_minute
          codes = if end_minute > start_minute
            SHIFT_RANGES.filter_map do |_, code, hours|
              code if start_minute < hours.end * 60 && end_minute > hours.begin * 60
            end
          else
            [shift_for(start_time.hour)]
          end
          codes.each { |code| shift_occurrences[[date.cwday, code]] << date }
        end
        customer_geography = CustomerGeography.new(
          appointments: appointments,
          sales_by_appointment: sales_by_appointment,
          include_sales: @include_sales
        ).call

        days = Array.new(7) { |index| blank_group(WEEKDAYS[index]) }
        shifts = %w[Manhã Tarde Noite].index_with { |name| blank_group(name) }
        hours = (0..23).index_with { |hour| blank_group(format('%02d:00', hour)) }
        heatmap = Array.new(7) { Array.new(24, 0) }
        regions = {}
        origin_groups = BookingOrigin::LABELS.to_h do |key, label|
          [key, blank_group(label).merge(key: key)]
        end
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

          origin_group = nil
          origin = booking_origin.category(appointment, service_date)
          if origin
            origin_group = origin_groups.fetch(origin)
            increment_patient(origin_group, appointment)
            day[origin] += 1
            region[origin] += 1
          end

          appointment_sales = sales_by_appointment.fetch(appointment.id, [])
          apply_sales(day, appointment_sales)
          apply_sales(region, appointment_sales)
          apply_sales(origin_group, appointment_sales) if origin_group
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
          origin_group[:exams] += 1 if origin_group
          # An entered-on-another-day prescription cannot reliably identify the exam hour.
          created = prescription.created_at&.in_time_zone
          next unless created&.to_date == service_date

          hour = created.hour
          shift_code = shift_for(hour)
          shift_occurrences[[service_date.cwday, shift_code]] << service_date if @include_shift_financials && service_date <= Date.current
          shift = shifts[hour < 12 ? 'Manhã' : hour < 18 ? 'Tarde' : 'Noite']
          shift[:exams] += 1
          hours[hour][:exams] += 1
          heatmap[service_date.cwday - 1][hour] += 1
          apply_sales(shift, appointment_sales)
          apply_sales(hours[hour], appointment_sales)
          if @include_shift_financials && !cached_shift_financials.key?(appointment.service_id)
            financial = shift_financials[[service_date.cwday, shift_code]]
            appointment_sales.each do |sale|
              financial[:sales_amount] += sale[:amount]
              financial[:receipts_amount] += receipts_by_order.fetch(sale[:order_id], 0.to_d)
            end
          end
        end

        if @include_shift_financials
          cached_shift_financials.each do |service_id, statistic|
            service_date = service_day.fetch(service_id)
            statistic.financial_by_exam_shift.each do |code, amounts|
              financial = shift_financials[[service_date.cwday, code]]
              financial[:sales_amount] += amounts.fetch("sales_amount", 0).to_d
              financial[:receipts_amount] += amounts.fetch("receipts_amount", 0).to_d
            end
          end
        end

        service_dates.each do |_, date|
          days[date.cwday - 1][:sessions] += 1
        end

        day_shifts = ranked_day_shifts(heatmap, shift_financials, shift_occurrences)
        if @include_shift_financials
          shifts.each_with_index do |(label, group), index|
            code = SHIFT_RANGES[index][1]
            matching = day_shifts.select { |entry| entry[:shift] == code }
            group[:receipts_amount] = matching.sum { |entry| entry[:receipts_amount] }
            count = matching.sum { |entry| entry[:occurrences] }
            group[:occurrences] = count
            group[:average_sales_amount] = count.positive? ? matching.sum { |entry| entry[:sales_amount] } / count : 0.to_d
            group[:average_receipts_amount] = count.positive? ? group[:receipts_amount] / count : 0.to_d
          end
        end

        all_groups = days + shifts.values + hours.values + regions.values + origin_groups.values
        all_groups.each { |group| finalize_sales(group) }

        {
          patients: appointments.size, attended: attended, exams: examined,
          sales: buyer_ids.size, orders: order_ids.size, sales_amount: sales_total,
          show_sales: @include_sales, show_shift_financials: @include_shift_financials,
          sessions: service_dates.size, days: days, shifts: shifts.values,
          hours: hours.values, heatmap: heatmap, day_shifts: day_shifts,
          booking_origins: origin_groups.values,
          advance_bookings: origin_groups[:advance][:patients],
          same_day_bookings: origin_groups[:same_day][:patients],
          rescheduled_same_day_bookings: origin_groups[:rescheduled_same_day][:patients],
          customer_geography: customer_geography,
          regions: regions.values.sort_by { |row| [-row[:attended], row[:label]] }
        }
      end

      private

      def ranked_day_shifts(heatmap, financials = {}, occurrences = {})
        ranking = heatmap.each_with_index.flat_map do |daily_hours, day_index|
          SHIFT_RANGES.map.with_index do |(name, code, hour_range), shift_index|
            key = [day_index + 1, code]
            financial = financials.fetch(key, {})
            count = occurrences.fetch(key, Set.new).size
            sales_amount = financial.fetch(:sales_amount, 0.to_d)
            receipts_amount = [financial.fetch(:receipts_amount, 0.to_d), 0.to_d].max
            { label: "#{WEEKDAYS[day_index]} · #{name}", weekday: day_index + 1,
              shift: code, shift_order: shift_index, exams: daily_hours[hour_range].sum,
              occurrences: count, sales_amount: sales_amount, receipts_amount: receipts_amount,
              average_sales_amount: count.positive? ? sales_amount / count : 0.to_d,
              average_receipts_amount: count.positive? ? receipts_amount / count : 0.to_d }
          end
        end
        ranking.select! { |row| row[:exams].positive? }
        ranking.sort_by! { |row| [-row[:exams], row[:weekday], row[:shift_order]] }
        ranking.each { |row| row.delete(:shift_order) }
      end

      def shift_for(hour)
        hour < 12 ? "morning" : hour < 18 ? "afternoon" : "night"
      end

      # Same full future-visit candidate set as FinancialMetrics. Filtering a
      # location, region or captador cannot reassign an order to an older visit.
      def attributed_sales(appointments, service_dates)
        attended = appointments.select(&:attendance?)
        return {} if attended.empty?

        customers = LeadsConversion.where(clinic_management_lead_id: attended.map(&:lead_id))
                                   .distinct.pluck(:customer_id)
        return {} if customers.empty?

        lead_ids = LeadsConversion.where(customer_id: customers).pluck(:clinic_management_lead_id)
        visits = Appointment.joins(:service)
                            .where(lead_id: lead_ids, attendance: true)
                            .where(clinic_management_services: { date: @start_date..(@end_date + SalesAttribution::WINDOW_DAYS.days) })
                            .includes(:service).to_a
        dates = visits.to_h { |appointment| [appointment.service_id, appointment.service.date] }
        SalesAttribution.new(appointments: visits, service_dates: dates).call
      end

      def shift_financial_snapshots(service_dates)
        return {} unless @include_sales && @region_id.nil? && @referral_id.nil?

        ServiceStatistic.where(service_id: service_dates.keys,
                               sales_metrics_version: ServiceStatistics::FinancialMetrics::VERSION)
                        .where.not(sales_computed_at: nil)
                        .index_by(&:service_id)
                        .select do |service_id, statistic|
          date = service_dates[service_id]
          date && date < Date.current &&
            (!ServiceStatistics::Policy.sales_frozen?(date) || statistic.sales_frozen_at.present?)
        end
      end

      def blank_group(label)
        { label: label, patients: 0, attended: 0, exams: 0, sessions: 0,
          advance: 0, same_day: 0, rescheduled_same_day: 0, after_date: 0,
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
