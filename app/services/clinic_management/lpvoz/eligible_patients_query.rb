# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class EligiblePatientsQuery
      SUPPORTED_LPVOZ_STATUSES = %w[never_called no_answer technical_failure].freeze

      def initialize(program:, now: Time.current)
        @program = program
        @now = now
      end

      def relation
        @relation ||= apply_filters(base_relation).distinct
      end

      def count
        relation.count(:id)
      end

      def next_candidate
        relation.first
      end

      private

      attr_reader :program, :now

      def base_relation
        one_year_ago = current_date - 1.year
        recently_attended = ClinicManagement::Appointment
          .joins(:service)
          .where(
            "clinic_management_appointments.attendance = ? AND clinic_management_services.date >= ?",
            true,
            one_year_ago
          )
          .select(:lead_id)

        ClinicManagement::Lead
          .joins("INNER JOIN clinic_management_appointments AS main_apt ON main_apt.id = (#{latest_appointment_subquery})")
          .joins("INNER JOIN clinic_management_services AS main_svc ON main_svc.id = main_apt.service_id")
          .joins("INNER JOIN clinic_management_invitations AS main_inv ON main_inv.id = main_apt.invitation_id")
          .joins("LEFT JOIN clinic_management_lpvoz_operations AS latest_lpvop ON latest_lpvop.id = (#{latest_operation_subquery})")
          .select("clinic_management_leads.*", "main_apt.id AS current_appointment_id", "main_svc.date AS service_date")
          .where.not(id: recently_attended)
          .where("main_svc.date < ?", current_date)
          .where("main_apt.status IS NULL OR main_apt.status NOT IN (?)", %w[cancelado remarcado])
          .where("clinic_management_leads.phone ~ ?", "^[0-9]{10,11}$")
          .where.not(id: attempted_today_subquery)
          .order("main_svc.date DESC, main_apt.id DESC")
      end

      def apply_filters(scope)
        scope = apply_patient_type(scope)
        scope = apply_period(scope)
        scope = apply_region(scope)
        scope = apply_service_location(scope)
        scope = apply_interest_status(scope)
        apply_lpvoz_status(scope)
      end

      def apply_patient_type(scope)
        case filters["patient_type"]
        when "absent"
          scope.where("main_apt.attendance = ?", false)
        when "attended_year_ago"
          scope.where("main_apt.attendance = ? AND main_svc.date < ?", true, current_date - 1.year)
        else
          scope.where(
            "(main_apt.attendance = ? OR (main_apt.attendance = ? AND main_svc.date < ?))",
            false,
            true,
            current_date - 1.year
          )
        end
      end

      def apply_period(scope)
        days = Integer(filters["period_days"], exception: false)
        return scope unless days&.positive?

        scope.where("main_svc.date >= ?", current_date - days.days)
      end

      def apply_region(scope)
        region_id = Integer(filters["region_id"], exception: false)
        region_id&.positive? ? scope.where("main_inv.region_id = ?", region_id) : scope
      end

      def apply_service_location(scope)
        value = filters["service_location_id"]
        return scope if value.nil? || value == "any"

        case value.to_s
        when ""
          scope.where("main_svc.service_location_id IS NULL")
        when "all"
          scope.where("main_svc.service_location_id IS NOT NULL")
        else
          scope.where("main_svc.service_location_id = ?", value)
        end
      end

      def apply_interest_status(scope)
        case filters["interest_status"]
        when "no_interest"
          scope.where(no_interest: true)
        when "wrong_phone"
          scope.where(wrong_phone: true)
        else
          scope.where(
            hidden_from_absent: [false, nil],
            no_interest: [false, nil],
            wrong_phone: [false, nil]
          )
        end
      end

      def apply_lpvoz_status(scope)
        statuses = Array(filters["lpvoz_statuses"]).map(&:to_s) & SUPPORTED_LPVOZ_STATUSES
        return scope if statuses.blank?

        predicates = []
        predicates << "latest_lpvop.id IS NULL" if statuses.include?("never_called")
        if statuses.include?("no_answer")
          predicates << <<~SQL.squish
            latest_lpvop.result ->> 'classification' IN ('no_answer', 'voicemail')
            OR latest_lpvop.result ->> 'outcome' IN ('no_answer', 'voicemail')
          SQL
        end
        if statuses.include?("technical_failure")
          predicates << <<~SQL.squish
            latest_lpvop.status = 'failed'
            OR latest_lpvop.result ->> 'classification' = 'technical_failure'
          SQL
        end

        scope.where(predicates.map { |predicate| "(#{predicate})" }.join(" OR "))
      end

      def filters
        program.filters.to_h.stringify_keys
      end

      def latest_appointment_subquery
        <<~SQL.squish
          SELECT appointment.id
          FROM clinic_management_appointments appointment
          INNER JOIN clinic_management_services service ON service.id = appointment.service_id
          WHERE appointment.lead_id = clinic_management_leads.id
          ORDER BY service.date DESC, appointment.id DESC
          LIMIT 1
        SQL
      end

      def latest_operation_subquery
        account_id = Integer(program.account_id)
        <<~SQL.squish
          SELECT operation.id
          FROM clinic_management_lpvoz_operations operation
          WHERE operation.account_id = #{account_id}
            AND operation.lead_id = clinic_management_leads.id
          ORDER BY operation.created_at DESC, operation.id DESC
          LIMIT 1
        SQL
      end

      def attempted_today_subquery
        ClinicManagement::LpvozOperation
          .where(account_id: program.account_id, created_at: program.local_day_range(now))
          .select(:lead_id)
      end

      def current_date
        @current_date ||= now.in_time_zone(program.time_zone).to_date
      end
    end
  end
end
