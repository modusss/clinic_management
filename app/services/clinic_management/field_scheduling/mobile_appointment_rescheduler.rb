# frozen_string_literal: true

module ClinicManagement
  module FieldScheduling
    # Rebooks one captador appointment transactionally and preserves the audit link.
    class MobileAppointmentRescheduler
      class InvalidAppointment < StandardError; end

      Result = Struct.new(:appointment, :created, keyword_init: true)

      def initialize(policy:, appointment:, attributes:)
        @policy = policy
        @appointment = appointment
        @attributes = attributes.to_h.deep_symbolize_keys
      end

      def call
        request_id = attributes[:client_request_id].to_s
        raise InvalidAppointment, "Identificador da operação ausente." if request_id.blank?

        existing = policy.appointment_scope.find_by(mobile_request_id: request_id)
        return Result.new(appointment: existing, created: false) if existing

        replacement = appointment.with_lock do
          raise InvalidAppointment, "Esta marcação não pode mais ser remarcada." unless appointment.status == "agendado"

          service = policy.find_service!(attributes[:service_id])
          invitation = appointment.lead.invitations.create!(
            referral: policy.referral,
            region: appointment.invitation.region,
            patient_name: appointment.invitation.patient_name,
            notes: appointment.invitation.notes,
            date: Date.current
          )
          created = ClinicManagement::AppointmentBooking.new(
            service: service,
            allow_overbooking: ActiveModel::Type::Boolean.new.cast(attributes[:allow_overbooking])
          ).create_consecutive!(
            appointment_attributes: [{
              invitation: invitation,
              lead: appointment.lead,
              status: "agendado",
              referral_code: policy.referral.code,
              registered_by_user_id: policy.user.id,
              mobile_request_id: request_id,
              rescheduled_from_appointment_id: appointment.id
            }],
            starting_at: parse_time(attributes[:scheduled_at])
          ).first
          appointment.update!(status: "remarcado")
          appointment.lead.update!(last_appointment_id: created.id)
          created
        end

        Result.new(appointment: replacement, created: true)
      rescue ActiveRecord::RecordNotUnique
        existing = policy.appointment_scope.find_by!(mobile_request_id: request_id)
        Result.new(appointment: existing, created: false)
      end

      private

      attr_reader :policy, :appointment, :attributes

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        raise ClinicManagement::AppointmentBooking::UnavailableTime, "Escolha um horário válido."
      end
    end
  end
end
