# frozen_string_literal: true

module ClinicManagement
  # Resolves every time placeholder used by clinic appointment messages.
  #
  # ESSENTIAL:
  # - Legacy placeholders always describe the full Service attendance range.
  # - Scheduled placeholders describe the individual Appointment slot.
  # - Services without an individual slot fall back to the full range so
  #   existing automated messages never receive an empty time.
  class AppointmentMessageTimeResolver
    PLACEHOLDER_KEYS = %w[
      HORARIO_DE_INICIO
      HORARIO_DE_TERMINO
      HORARIO_AGENDADO_INICIO
      HORARIO_AGENDADO_TERMINO
      CORRESPONDENCIA_DO_HORARIO
    ].freeze

    class << self
      # @param appointment [ClinicManagement::Appointment, Object, nil]
      # @return [Hash<String, String>] placeholder key => formatted HH:MM value
      def resolve(appointment)
        service = appointment&.service
        range_start = service&.start_time || Time.zone.parse("14:00")
        range_end = service&.end_time || Time.zone.parse("17:00")
        scheduled_start = effective_time(appointment, :effective_start_time) || range_start
        scheduled_end = effective_time(appointment, :effective_end_time) || range_end

        {
          "HORARIO_DE_INICIO" => format_time(range_start),
          "HORARIO_DE_TERMINO" => format_time(range_end),
          "HORARIO_AGENDADO_INICIO" => format_time(scheduled_start),
          "HORARIO_AGENDADO_TERMINO" => format_time(scheduled_end),
          "CORRESPONDENCIA_DO_HORARIO" => correspondence_for(
            appointment,
            range_start: range_start,
            range_end: range_end
          )
        }
      end

      private

      # @param appointment [Object, nil]
      # @param method_name [Symbol]
      # @return [Time, nil]
      def effective_time(appointment, method_name)
        return unless appointment&.respond_to?(method_name)

        appointment.public_send(method_name)
      end

      # Builds the complete customer-facing time expression.
      #
      # @param appointment [Object, nil]
      # @param range_start [Time]
      # @param range_end [Time]
      # @return [String] e.g. "8h", "8:45h", or "08:00h às 12:00h"
      def correspondence_for(appointment, range_start:, range_end:)
        scheduled_at = appointment.public_send(:scheduled_at) if appointment&.respond_to?(:scheduled_at)
        return human_time(scheduled_at) if scheduled_at.present?

        "#{format_time(range_start)}h às #{format_time(range_end)}h"
      end

      # @param value [Time, nil]
      # @return [String]
      def format_time(value)
        value&.strftime("%H:%M").to_s
      end

      # @param value [Time]
      # @return [String]
      def human_time(value)
        minutes = value.strftime("%M")
        minutes == "00" ? "#{value.hour}h" : "#{value.hour}:#{minutes}h"
      end
    end
  end
end
