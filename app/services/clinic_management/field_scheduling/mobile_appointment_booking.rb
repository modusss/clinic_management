# frozen_string_literal: true

module ClinicManagement
  module FieldScheduling
    # Creates an idempotent captador booking while reusing the central slot lock.
    class MobileAppointmentBooking
      class InvalidPatient < StandardError; end

      Result = Struct.new(:appointment, :created, keyword_init: true)

      def initialize(policy:, attributes:)
        @policy = policy
        @attributes = attributes.to_h.deep_symbolize_keys
      end

      def call
        request_id = attributes[:client_request_id].to_s
        raise InvalidPatient, "Identificador da operação ausente." if request_id.blank?

        existing = policy.appointment_scope.find_by(mobile_request_id: request_id)
        return Result.new(appointment: existing, created: false) if existing

        appointment = ActiveRecord::Base.transaction do
          service = policy.find_service!(attributes[:service_id])
          patient = attributes.fetch(:patient, {})
          lead = resolve_lead(patient)
          patient_name = patient[:patient_name].to_s.strip
          raise InvalidPatient, "Informe o nome do paciente." if patient_name.blank?

          invitation = lead.invitations.create!(
            referral: policy.referral,
            region: resolve_region(patient[:region_id]),
            patient_name: patient_name,
            notes: patient[:notes].presence,
            date: Date.current
          )
          created = ClinicManagement::AppointmentBooking.new(
            service: service,
            allow_overbooking: ActiveModel::Type::Boolean.new.cast(attributes[:allow_overbooking])
          ).create_consecutive!(
            appointment_attributes: [{
              invitation: invitation,
              lead: lead,
              status: "agendado",
              referral_code: policy.referral.code,
              registered_by_user_id: policy.user.id,
              mobile_request_id: request_id
            }],
            starting_at: parse_time(attributes[:scheduled_at])
          ).first
          lead.update!(last_appointment_id: created.id)
          created
        end

        Result.new(appointment: appointment, created: true)
      rescue ActiveRecord::RecordNotUnique
        existing = policy.appointment_scope.find_by!(mobile_request_id: request_id)
        Result.new(appointment: existing, created: false)
      end

      private

      attr_reader :policy, :attributes

      def resolve_lead(patient)
        return policy.find_lead!(patient[:lead_id]) if patient[:lead_id].present?

        phone = patient[:phone].to_s.gsub(/\D/, "")
        raise InvalidPatient, "Informe um telefone válido com DDD." unless phone.match?(/\A\d{10,11}\z/)

        existing = policy.lead_scope.find_by(phone: phone)
        return merge_blank_lead_fields(existing, patient) if existing

        ClinicManagement::Lead.create!(
          name: patient[:responsible_name].presence || patient[:patient_name],
          phone: phone,
          address: patient[:address].presence
        )
      end

      def merge_blank_lead_fields(lead, patient)
        updates = {}
        updates[:name] = patient[:responsible_name] if lead.name.blank? && patient[:responsible_name].present?
        updates[:address] = patient[:address] if lead.address.blank? && patient[:address].present?
        lead.update!(updates) if updates.any?
        lead
      end

      def resolve_region(region_id)
        return ClinicManagement::Region.ensure_local! if region_id.blank?

        ClinicManagement::Region.active.find(region_id)
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        raise ClinicManagement::AppointmentBooking::UnavailableTime, "Escolha um horário válido."
      end
    end
  end
end
