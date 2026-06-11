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
  end
end
