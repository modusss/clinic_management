module ClinicManagement
  # ESSENTIAL: Conversion metrics for services#index aggregated views (weekly/monthly).
  # Visible only when is_manager_above? (manager + owner) — business statistics, not staff ops.
  module ServicesStatsHelper
    # @param numerator [Numeric]
    # @param denominator [Numeric]
    # @return [Float] percentage rounded to one decimal, or 0.0 when denominator is zero
    def services_conversion_rate(numerator, denominator)
      return 0.0 if denominator.to_i.zero?

      (numerator.to_f / denominator * 100).round(1)
    end

    # CSS tone for attendance conversion (patients → attended).
    # @param rate [Float]
    # @return [String] red | orange | green
    def services_attendance_rate_tone(rate)
      return "red" if rate < 30.0
      return "orange" if rate < 50.0

      "green"
    end

    # CSS tone for sales conversion (attended → sales).
    # @param rate [Float]
    # @return [String] red | orange | green
    def services_sales_rate_tone(rate)
      services_attendance_rate_tone(rate)
    end

    # CSS tone for final conversion (patients → sales) — lower bar because it is a compound funnel step.
    # @param rate [Float]
    # @return [String] red | orange | green
    def services_final_rate_tone(rate)
      return "red" if rate < 10.0
      return "orange" if rate < 20.0

      "green"
    end

    # Builds inline width style for a progress bar relative to the period maximum.
    # @param value [Numeric]
    # @param max_value [Numeric]
    # @return [String] CSS width percentage
    def services_stats_bar_width(value, max_value)
      return "0%" if max_value.to_i.zero?

      width = (value.to_f / max_value * 100).clamp(4, 100)
      "#{width.round(1)}%"
    end

    # Renders a conversion cell: percentage + ratio caption.
    # @param rate [Float]
    # @param numerator [Numeric]
    # @param denominator [Numeric]
    # @param tone [String] red | orange | green
    # @return [String] HTML safe
    def services_conversion_cell(rate, numerator, denominator, tone:)
      content_tag(:div, class: "services-stats-conversion services-stats-conversion--#{tone}") do
        safe_join([
          content_tag(:span, "#{format('%.1f', rate)}%", class: "services-stats-conversion__rate"),
          content_tag(:span, "#{numerator} de #{denominator}", class: "services-stats-conversion__ratio")
        ])
      end
    end

    # Computes operational day metrics for one or more ClinicManagement::Service records.
    #
    # ESSENTIAL: Uses the exact same valid-appointment filter as the day table rows
    # (invitation.patient_name.present? && lead.name.present?, plus referral_code when
    # scoped to a specific referral) so "Total na lista" always matches the rendered rows.
    #
    # @param services [ClinicManagement::Service, Enumerable<ClinicManagement::Service>]
    # @param referral [Referral, nil] optional captador filter for show_by_referral
    # @return [Hash] Operational counters and percentages for the day summary bar
    def service_day_metrics(services, referral: nil)
      service_list = Array(services).compact
      appointments = service_list.flat_map do |service|
        service.appointments.to_a.select do |ap|
          valid_patient = ap&.invitation&.patient_name.present? && ap&.lead&.name.present?
          matches_referral = referral.nil? || ap.referral_code == referral.code
          valid_patient && matches_referral
        end
      end

      total = appointments.size
      canceled = appointments.count { |ap| ap.status.to_s.downcase == "cancelado" }
      rescheduled = appointments.count { |ap| ap.status.to_s.downcase == "remarcado" }
      active_appointments = appointments.reject { |ap| ap.status.to_s.downcase.in?(%w[cancelado remarcado]) }
      active = active_appointments.size

      confirmed = appointments.count { |ap| ap.confirmed == true }
      confirmed_active = active_appointments.count { |ap| ap.confirmed == true }
      attended = appointments.count { |ap| ap.attendance == true }
      pending_or_absent = active_appointments.count { |ap| ap.attendance != true }

      reference_date = service_list.map(&:date).compact.max || Date.current
      past_service = reference_date < Date.current
      today_service = reference_date == Date.current
      any_canceled = service_list.any? { |s| s.respond_to?(:canceled) && s.canceled }

      status_badge_label, status_badge_tone = if any_canceled
        ["Cancelado", "red"]
      elsif past_service
        ["Encerrado", "slate"]
      elsif today_service
        ["Hoje", "emerald"]
      else
        ["Programado", "blue"]
      end

      rate_denominator = active.positive? ? active : total
      attendance_rate = services_conversion_rate(attended, rate_denominator)
      pending_rate = services_conversion_rate(pending_or_absent, rate_denominator)
      confirmation_rate = services_conversion_rate(confirmed, total)

      {
        total: total,
        active: active,
        confirmed: confirmed,
        confirmed_active: confirmed_active,
        confirmation_rate: confirmation_rate,
        attended: attended,
        attendance_rate: attendance_rate,
        pending_or_absent: pending_or_absent,
        pending_rate: pending_rate,
        pending_label: past_service ? "Faltaram" : "Aguardando",
        pending_subtitle: "#{format('%.1f', pending_rate).tr('.', ',')}% do total",
        attended_subtitle: "#{format('%.1f', attendance_rate).tr('.', ',')}% do total",
        past_service: past_service,
        status_badge_label: status_badge_label,
        status_badge_tone: status_badge_tone,
        rescheduled: rescheduled,
        canceled: canceled
      }
    end

    # Resolves the client-side filter state for a patient row in the day/service list.
    #
    # @param appointment [ClinicManagement::Appointment]
    # @return [String] "present" | "pending" | "rescheduled" | "canceled"
    def appointment_patient_filter_state(appointment)
      return "present" if appointment.attendance == true

      status = appointment.status.to_s.downcase
      return "canceled" if status == "cancelado"
      return "rescheduled" if status == "remarcado"

      "pending"
    end
  end
end
