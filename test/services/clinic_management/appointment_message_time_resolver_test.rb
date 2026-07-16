# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/time/zones"
require "minitest/autorun"
require "ostruct"
require_relative "../../../app/services/clinic_management/appointment_message_time_resolver"

Time.zone ||= "UTC"

module ClinicManagement
  class AppointmentMessageTimeResolverTest < Minitest::Test
    def test_keeps_legacy_placeholders_bound_to_the_service_range
      appointment = scheduled_appointment

      values = AppointmentMessageTimeResolver.resolve(appointment)

      assert_equal "08:00", values.fetch("HORARIO_DE_INICIO")
      assert_equal "12:00", values.fetch("HORARIO_DE_TERMINO")
    end

    def test_resolves_individual_scheduled_placeholders_from_the_appointment
      appointment = scheduled_appointment

      values = AppointmentMessageTimeResolver.resolve(appointment)

      assert_equal "08:20", values.fetch("HORARIO_AGENDADO_INICIO")
      assert_equal "08:40", values.fetch("HORARIO_AGENDADO_TERMINO")
      assert_equal "8:20h", values.fetch("CORRESPONDENCIA_DO_HORARIO")
    end

    def test_omits_minutes_from_the_correspondence_when_the_scheduled_time_is_exact
      appointment = scheduled_appointment(
        scheduled_at: Time.zone.parse("08:00"),
        effective_end_time: Time.zone.parse("08:20")
      )

      values = AppointmentMessageTimeResolver.resolve(appointment)

      assert_equal "8h", values.fetch("CORRESPONDENCIA_DO_HORARIO")
    end

    def test_falls_back_to_the_service_range_when_there_is_no_individual_time
      service = service_range
      appointment = OpenStruct.new(
        service: service,
        scheduled_at: nil,
        effective_start_time: service.start_time,
        effective_end_time: service.end_time
      )

      values = AppointmentMessageTimeResolver.resolve(appointment)

      assert_equal "08:00", values.fetch("HORARIO_AGENDADO_INICIO")
      assert_equal "12:00", values.fetch("HORARIO_AGENDADO_TERMINO")
      assert_equal "08:00h às 12:00h", values.fetch("CORRESPONDENCIA_DO_HORARIO")
    end

    private

    def scheduled_appointment(scheduled_at: Time.zone.parse("08:20"), effective_end_time: Time.zone.parse("08:40"))
      OpenStruct.new(
        service: service_range,
        scheduled_at: scheduled_at,
        effective_start_time: scheduled_at,
        effective_end_time: effective_end_time
      )
    end

    def service_range
      OpenStruct.new(
        start_time: Time.zone.parse("08:00"),
        end_time: Time.zone.parse("12:00")
      )
    end
  end
end
