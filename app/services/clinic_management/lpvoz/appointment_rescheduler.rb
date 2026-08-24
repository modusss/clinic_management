# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class AppointmentRescheduler
      class InvalidRequest < StandardError; end

      Result = Data.define(:appointment, :created)

      def initialize(operation:, service_id:, scheduled_at:, idempotency_key:)
        @operation = operation
        @service_id = service_id
        @scheduled_at = scheduled_at
        @idempotency_key = "lpvoz:#{idempotency_key}"
      end

      def call
        requested_time = Time.zone.parse(scheduled_at.to_s)
        raise InvalidRequest, "Escolha um horário válido." unless requested_time

        existing = ClinicManagement::Appointment.find_by(mobile_request_id: idempotency_key)
        if existing
          same_request = existing.service_id.to_s == service_id.to_s &&
            existing.scheduled_at&.change(usec: 0) == requested_time.change(usec: 0) &&
            existing.rescheduled_from_appointment_id == operation.appointment_id
          raise InvalidRequest, "Chave de idempotência já utilizada com outra remarcação." unless same_request

          return Result.new(appointment: existing, created: false)
        end

        replacement = operation.appointment.with_lock do
          source = operation.appointment
          raise InvalidRequest, "Esta marcação não pode mais ser remarcada." unless source.status == "agendado"

          service = eligible_service_scope.find(service_id)
          invitation = source.lead.invitations.create!(
            referral: source.invitation.referral,
            region: source.invitation.region,
            patient_name: source.invitation.patient_name,
            notes: source.invitation.notes,
            date: Date.current
          )
          created = ClinicManagement::AppointmentBooking.new(service:).create_consecutive!(
            appointment_attributes: [{
              invitation:,
              lead: source.lead,
              status: "agendado",
              referral_code: source.referral_code,
              registered_by_user_id: nil,
              mobile_request_id: idempotency_key,
              rescheduled_from_appointment_id: source.id
            }],
            starting_at: requested_time
          ).first
          source.update!(status: "remarcado")
          source.lead.update!(last_appointment_id: created.id)
          created
        end
        Result.new(appointment: replacement, created: true)
      rescue ArgumentError
        raise InvalidRequest, "Escolha um horário válido."
      rescue ActiveRecord::RecordNotUnique
        Result.new(appointment: ClinicManagement::Appointment.find_by!(mobile_request_id: idempotency_key), created: false)
      end

      private

      attr_reader :operation, :service_id, :scheduled_at, :idempotency_key

      def eligible_service_scope
        source_service = operation.appointment.service
        scope = ClinicManagement::Service.upcoming.where(service_location_id: source_service.service_location_id)
        scope = scope.where(service_type_id: source_service.service_type_id) if source_service.service_type_id.present?
        scope
      end
    end
  end
end
