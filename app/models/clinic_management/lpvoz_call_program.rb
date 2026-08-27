# frozen_string_literal: true

require "tzinfo"

module ClinicManagement
  class LpvozCallProgram < ApplicationRecord
    self.table_name = "clinic_management_lpvoz_call_programs"

    DEFAULT_TIME_WINDOWS = [
      { "start" => "08:00", "end" => "12:00" },
      { "start" => "13:00", "end" => "17:00" }
    ].freeze
    DEFAULT_FILTERS = {
      "patient_type" => "absent",
      "period_days" => "30",
      "service_location_id" => "",
      "interest_status" => "visible",
      "lpvoz_statuses" => %w[never_called no_answer]
    }.freeze
    ACTIVE_OPERATION_STATUSES = %w[queued dispatching accepted in_progress].freeze
    TERMINAL_OPERATION_STATUSES = %w[completed failed needs_attention canceled].freeze
    ANSWERED_EVENT_TYPES = %w[call.answered call.in_progress].freeze

    belongs_to :account, class_name: "::Account"
    belongs_to :lpvoz_connection, class_name: "ClinicManagement::LpvozConnection"
    belongs_to :created_by, class_name: "::User", optional: true
    has_many :lpvoz_operations,
             class_name: "ClinicManagement::LpvozOperation",
             dependent: :restrict_with_error

    enum :status, { draft: "draft", active: "active", paused: "paused" },
         default: :draft,
         validate: true

    before_validation :normalize_configuration

    validates :name, presence: true, length: { maximum: 120 }
    validates :agent_key, presence: true,
                          format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :daily_limit, numericality: { only_integer: true, in: 1..1_000 }
    validate :account_matches_connection
    validate :time_zone_is_valid
    validate :weekdays_are_valid
    validate :time_windows_are_valid

    scope :recent_first, -> { order(updated_at: :desc) }

    def activate!
      update!(status: :active, activated_at: Time.current, paused_at: nil)
    end

    def pause!
      update!(status: :paused, paused_at: Time.current)
    end

    def within_call_window?(time = Time.current)
      local_time = time.in_time_zone(time_zone)
      return false unless weekdays.include?(local_time.wday)

      minute = (local_time.hour * 60) + local_time.min
      time_windows.any? do |window|
        minute >= minutes_for(window.fetch("start")) && minute < minutes_for(window.fetch("end"))
      end
    end

    def local_day_range(time = Time.current)
      local_time = time.in_time_zone(time_zone)
      local_time.beginning_of_day..local_time.end_of_day
    end

    def calls_today(time = Time.current)
      lpvoz_operations.where(created_at: local_day_range(time)).count
    end

    # The operational ceiling represents conversations actually answered, not
    # dial attempts. One operation can receive duplicate/out-of-order provider
    # callbacks, hence the distinct operation count.
    def answered_calls_today(time = Time.current)
      lpvoz_operations
        .where(created_at: local_day_range(time))
        .joins(:lpvoz_events)
        .where(clinic_management_lpvoz_events: { event_type: ANSWERED_EVENT_TYPES })
        .where(
          "result ->> 'classification' IS NULL OR result ->> 'classification' NOT IN (?)",
          %w[no_answer voicemail]
        )
        .distinct
        .count
    end

    def daily_limit_reached?(time = Time.current)
      answered_calls_today(time) >= daily_limit
    end

    def active_operation?
      lpvoz_operations.where(status: ACTIVE_OPERATION_STATUSES).exists?
    end

    private

    def normalize_configuration
      self.weekdays = Array(weekdays).filter_map { |value| Integer(value, exception: false) }.uniq.sort
      self.time_windows = Array(time_windows).filter_map do |window|
        values = window.respond_to?(:to_h) ? window.to_h.stringify_keys : {}
        next if values["start"].blank? && values["end"].blank?

        { "start" => values["start"].to_s, "end" => values["end"].to_s }
      end
      self.filters = DEFAULT_FILTERS.merge((filters || {}).to_h.stringify_keys)
      self.filters["lpvoz_statuses"] = Array(self.filters["lpvoz_statuses"]).map(&:to_s).uniq
    end

    def account_matches_connection
      return if lpvoz_connection.blank? || account_id == lpvoz_connection.account_id

      errors.add(:lpvoz_connection, "precisa pertencer à mesma conta")
    end

    def time_zone_is_valid
      TZInfo::Timezone.get(time_zone.to_s)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:time_zone, "não é válido")
    end

    def weekdays_are_valid
      return if weekdays.present? && weekdays.all? { |day| day.in?(0..6) }

      errors.add(:weekdays, "precisa conter ao menos um dia válido")
    end

    def time_windows_are_valid
      if time_windows.blank?
        errors.add(:time_windows, "precisa conter ao menos uma janela")
        return
      end

      ranges = time_windows.filter_map do |window|
        start_minute = parse_minutes(window["start"])
        end_minute = parse_minutes(window["end"])
        unless start_minute && end_minute && start_minute < end_minute
          errors.add(:time_windows, "contém um intervalo inválido")
          next
        end
        start_minute...end_minute
      end

      ranges.combination(2).each do |left, right|
        if left.cover?(right.begin) || right.cover?(left.begin)
          errors.add(:time_windows, "não pode conter intervalos sobrepostos")
          break
        end
      end
    end

    def parse_minutes(value)
      match = value.to_s.match(/\A([01]\d|2[0-3]):([0-5]\d)\z/)
      match && (match[1].to_i * 60) + match[2].to_i
    end

    def minutes_for(value)
      parse_minutes(value) || 0
    end
  end
end
