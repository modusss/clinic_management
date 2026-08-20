# frozen_string_literal: true

module ClinicManagement
  module FieldScheduling
    # Defines the captador's scheduling data boundary from the authenticated token.
    class AccessPolicy
      class Forbidden < StandardError; end

      attr_reader :account, :referral, :user

      def initialize(account:, referral:, user:)
        @account = account
        @referral = referral
        @user = user
      end

      def allowed_locations
        return ClinicManagement::ServiceLocation.none unless account.multi_service_locations_enabled?

        referral.allowed_service_locations.order(:name)
      end

      def service_scope
        allowed_ids = allowed_locations.pluck(:id)
        ClinicManagement::Service.upcoming.where(service_location_id: [nil, *allowed_ids])
      end

      def services_for_location(scope, location_id)
        return scope.where(service_location_id: nil) if location_id.blank? || location_id.to_s == "internal"

        id = Integer(location_id, exception: false)
        raise Forbidden, "Local de atendimento não permitido." unless id && allowed_locations.where(id: id).exists?

        scope.where(service_location_id: id)
      end

      def find_service!(id)
        service_scope.find(id)
      end

      def appointment_scope
        ClinicManagement::Appointment
          .joins(:invitation)
          .where(clinic_management_invitations: { referral_id: referral.id })
      end

      def lead_scope
        return ClinicManagement::Lead.all if referral.can_access_leads?

        ClinicManagement::Lead
          .joins(:invitations)
          .where(clinic_management_invitations: { referral_id: referral.id })
          .distinct
      end

      def find_lead!(id)
        lead_scope.find(id)
      end
    end
  end
end
