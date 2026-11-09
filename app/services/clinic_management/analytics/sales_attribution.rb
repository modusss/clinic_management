module ClinicManagement
  module Analytics
    # Assigns each eligible order to exactly one attended clinic appointment.
    # ESSENTIAL: The established service report uses a 30-day order window after
    # the service date. This drilldown resolves overlapping visits by the latest
    # eligible visit, preventing one sale from inflating several breakdowns.
    class SalesAttribution
      WINDOW_DAYS = 30

      def initialize(appointments:, service_dates:)
        @appointments = appointments.select(&:attendance?)
        @service_dates = service_dates
      end

      # @return [Hash<Integer, Array<Hash>>] appointment ID to attributed orders
      def call
        return {} if @appointments.empty?

        lead_ids = @appointments.map(&:lead_id).uniq
        customer_by_lead = LeadsConversion.where(clinic_management_lead_id: lead_ids)
                                          .pluck(:clinic_management_lead_id, :customer_id).to_h
        eligible_by_customer = Hash.new { |hash, key| hash[key] = [] }

        @appointments.each do |appointment|
          customer_id = customer_by_lead[appointment.lead_id]
          date = @service_dates[appointment.service_id]
          next unless customer_id && date

          eligible_by_customer[customer_id] << { appointment_id: appointment.id, date: date }
        end
        return {} if eligible_by_customer.empty?

        eligible_by_customer.each_value do |visits|
          visits.sort_by! { |visit| [-visit[:date].jd, -visit[:appointment_id]] }
        end

        earliest = @service_dates.values.min
        latest = @service_dates.values.max
        attributed = Hash.new { |hash, key| hash[key] = [] }
        Order.where(customer_id: eligible_by_customer.keys, canceled: [false, nil])
             .where(created_at: earliest.beginning_of_day..(latest + WINDOW_DAYS.days).end_of_day)
             .pluck(:id, :customer_id, :created_at, :total_amount).each do |order_id, customer_id, created_at, amount|
          order_date = created_at.in_time_zone.to_date
          visit = eligible_by_customer[customer_id].find do |candidate|
            order_date >= candidate[:date] && order_date <= candidate[:date] + WINDOW_DAYS.days
          end
          next unless visit

          attributed[visit[:appointment_id]] << {
            order_id: order_id, customer_id: customer_id, amount: (amount || 0).to_d
          }
        end
        attributed
      end
    end
  end
end
