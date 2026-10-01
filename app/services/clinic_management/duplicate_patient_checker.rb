# frozen_string_literal: true

module ClinicManagement
  # Finds appointments already created for a phone number in one service and
  # determines whether the submitted patient shares their first name.
  #
  # ESSENTIAL: A Lead represents the phone owner and can legitimately have
  # several patients. The duplicate rule therefore compares the normalized
  # first name stored in Invitation#patient_name, never Lead#name alone.
  class DuplicatePatientChecker
    Result = Struct.new(:service, :phone, :patient_name, :patients, :duplicate, keyword_init: true) do
      def duplicate?
        duplicate
      end
    end

    # @param service [ClinicManagement::Service, nil] selected attendance service
    # @param phone [String] raw or masked phone number entered by the user
    # @param patient_name [String] patient name entered by the user
    # @return [ClinicManagement::DuplicatePatientChecker::Result]
    def self.call(service:, phone:, patient_name:)
      new(service:, phone:, patient_name:).call
    end

    def initialize(service:, phone:, patient_name:)
      @service = service
      @phone = normalize_phone(phone)
      @patient_name = patient_name.to_s.strip
      @first_name = normalize_first_name(patient_name)
    end

    # Returns every active patient already registered with this phone in the
    # selected service, marking which entries share the submitted first name.
    #
    # @return [ClinicManagement::DuplicatePatientChecker::Result]
    def call
      patients = matching_appointments.filter_map do |appointment|
        name = appointment.invitation&.patient_name.to_s.strip
        next if name.blank?

        {
          patient_name: name,
          same_first_name: normalize_first_name(name) == first_name
        }
      end

      Result.new(
        service: service,
        phone: phone,
        patient_name: patient_name,
        patients: patients,
        duplicate: patients.any? { |patient| patient[:same_first_name] }
      )
    end

    private

    attr_reader :service, :phone, :patient_name, :first_name

    # Canceled and rescheduled appointments no longer occupy the attendance and
    # must not force staff to acknowledge a duplicate that is no longer active.
    def matching_appointments
      return ClinicManagement::Appointment.none if service.blank? || phone.blank? || first_name.blank?

      ClinicManagement::Appointment
        .joins(:lead)
        .includes(:invitation)
        .where(service_id: service.id)
        .where.not(status: %w[cancelado remarcado])
        .where(
          "REGEXP_REPLACE(COALESCE(clinic_management_leads.phone, ''), '[^0-9]', '', 'g') = ?",
          phone
        )
        .order(:id)
    end

    def normalize_phone(value)
      value.to_s.gsub(/\D/, "")
    end

    def normalize_first_name(value)
      I18n.transliterate(value.to_s).strip.downcase.split.first.to_s
    end
  end
end
