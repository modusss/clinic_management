# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class AvailabilitySlots
      MAX_SLOTS_PER_DAY = 3

      def initialize(services:, now: Time.current)
        @services = services
        @now = now
      end

      def call
        slots_by_date = Hash.new { |hash, date| hash[date] = [] }

        services.each do |service|
          day_slots = slots_by_date[service.date]
          remaining = MAX_SLOTS_PER_DAY - day_slots.size
          next unless remaining.positive?

          service.available_appointment_times
            .select { |time| time > now }
            .first(remaining)
            .each { |time| day_slots << serialize(service, time) }
        end

        slots_by_date.values.flatten
      end

      private

      attr_reader :services, :now

      def serialize(service, time)
        {
          service_id: service.id.to_s,
          scheduled_at: time.iso8601,
          label: I18n.l(time, format: "%d/%m às %H:%M"),
          location: service.service_location&.name || "Interno"
        }
      end
    end
  end
end
