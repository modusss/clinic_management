# frozen_string_literal: true

module ClinicManagement
  module FieldScheduling
    # Returns future services and real-time slot occupancy for one allowed location.
    class AvailabilityQuery
      class InvalidPeriod < StandardError; end

      MAX_DAYS = 31

      def initialize(policy:, from:, to:, location_id:, service_type_id: nil)
        @policy = policy
        @from = parse_date(from) || Date.current
        @to = parse_date(to) || (@from + 13.days)
        @location_id = location_id
        @service_type_id = service_type_id
      end

      def call
        raise InvalidPeriod, "Período de agenda inválido." if @to < @from || (@to - @from).to_i >= MAX_DAYS

        scope = policy.services_for_location(policy.service_scope, location_id)
        scope = scope.where(date: @from..@to)
        scope = scope.where(service_type_id: service_type_id) if service_type_id.present?
        scope.includes(:service_type, :service_location, :appointments).order(:date, :start_time).map do |service|
          ClinicManagement::FieldScheduling::ServiceAvailabilityJsonBuilder.call(service)
        end
      end

      private

      attr_reader :policy, :location_id, :service_type_id

      def parse_date(value)
        Date.iso8601(value.to_s) if value.present?
      rescue Date::Error
        raise InvalidPeriod, "Data de agenda inválida."
      end

    end
  end
end
