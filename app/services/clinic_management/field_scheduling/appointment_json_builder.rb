# frozen_string_literal: true

module ClinicManagement
  module FieldScheduling
    # Serializes one appointment for the Android scheduling experience.
    class AppointmentJsonBuilder
      def self.call(appointment)
        new(appointment).call
      end

      def initialize(appointment)
        @appointment = appointment
      end

      def call
        {
          id: appointment.id,
          status: appointment.status,
          confirmed: appointment.confirmed?,
          overbooked: appointment.overbooked?,
          patient_name: appointment.invitation&.patient_name,
          responsible_name: appointment.lead&.name,
          phone: appointment.lead&.phone,
          address: appointment.lead&.address,
          notes: appointment.invitation&.notes,
          scheduled_at: appointment.scheduled_at&.iso8601,
          scheduled_time_label: appointment.scheduled_time_label,
          can_reschedule: can_reschedule?,
          rescheduled_from_appointment_id: appointment.rescheduled_from_appointment_id,
          service: service_json
        }
      end

      private

      attr_reader :appointment

      def can_reschedule?
        service_date = appointment.service&.date
        appointment.status == "agendado" && service_date.present? && service_date.to_date >= Date.current
      end

      def service_json
        service = appointment.service
        {
          id: service.id,
          date: service.date.iso8601,
          start_time: service.start_time&.strftime("%H:%M"),
          end_time: service.end_time&.strftime("%H:%M"),
          booking_mode: service.booking_mode,
          interval_minutes: service.interval_minutes,
          service_type: service.service_type && { id: service.service_type.id, name: service.service_type.name },
          location: service.service_location ? { id: service.service_location.id.to_s, name: service.service_location.name } : { id: "internal", name: "Interno" }
        }
      end
    end
  end
end
