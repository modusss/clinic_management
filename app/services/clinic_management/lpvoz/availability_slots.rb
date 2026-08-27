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
        candidates_by_date = Hash.new { |hash, date| hash[date] = [] }

        services.each do |service|
          service.available_appointment_times
            .select { |time| time > now }
            .each do |time|
              candidates_by_date[service.date] << serialize(service, time)
            end
        end

        candidates_by_date.values.flat_map { |slots| representative_slots(slots) }
      end

      private

      attr_reader :services, :now

      # Keeps the payload compact without starving an entire period. Previously,
      # the first morning service consumed the daily limit before afternoon
      # services were inspected, so the voice agent could never answer a request
      # such as "tem pela tarde?" even when such slots existed.
      def representative_slots(slots)
        ordered = slots.sort_by { |slot| slot.fetch(:scheduled_at) }
        morning, afternoon = ordered.partition do |slot|
          Time.zone.parse(slot.fetch(:scheduled_at)).hour < 12
        end
        selected = [morning.first, afternoon.first].compact
        selected.concat((ordered - selected).first(MAX_SLOTS_PER_DAY - selected.size))
        selected.sort_by { |slot| slot.fetch(:scheduled_at) }
      end

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
