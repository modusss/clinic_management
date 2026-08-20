# frozen_string_literal: true

module ClinicManagement
  module FieldScheduling
    # Serializes one service with current occupancy without exposing patient data.
    class ServiceAvailabilityJsonBuilder
      def self.call(service)
        occupied = service.occupied_appointment_times.map { |time| time.change(sec: 0) }.to_set
        {
          id: service.id,
          date: service.date.iso8601,
          start_time: service.start_time&.strftime("%H:%M"),
          end_time: service.end_time&.strftime("%H:%M"),
          booking_mode: service.booking_mode,
          interval_minutes: service.interval_minutes,
          accepts_arrival_order: !service.scheduled?,
          service_type: service.service_type && { id: service.service_type.id, name: service.service_type.name },
          location: service.service_location ? { id: service.service_location.id.to_s, name: service.service_location.name } : { id: "internal", name: "Interno" },
          slots: service.appointment_times.map do |time|
            {
              scheduled_at: time.iso8601,
              label: time.strftime("%H:%M"),
              available: !occupied.include?(time.change(sec: 0))
            }
          end
        }
      end
    end
  end
end
