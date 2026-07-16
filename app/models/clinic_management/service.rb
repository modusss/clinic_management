module ClinicManagement
  class Service < ApplicationRecord
    BOOKING_MODES = ClinicManagement::TimeSlot::BOOKING_MODES
    INTERVAL_OPTIONS = ClinicManagement::TimeSlot::INTERVAL_OPTIONS

    has_many :appointments, dependent: :destroy
    belongs_to :service_type, optional: true
    belongs_to :service_location, optional: true, class_name: "ClinicManagement::ServiceLocation"
    has_one :service_statistic,
            class_name: "ClinicManagement::ServiceStatistic",
            dependent: :destroy

    # Adicione este escopo para buscar serviços futuros
    scope :upcoming, -> { where("date >= ?", Date.today).where(canceled: [false, nil]) }

    # Scope for filtering by service_location_id.
    # nil/blank = internal only; "all" = all externals; id = specific external.
    scope :for_location, ->(location_id) {
      case location_id.to_s
      when "all"
        where.not(service_location_id: nil)
      when ""
        where(service_location_id: nil)
      else
        where(service_location_id: location_id)
      end
    }

    validates :booking_mode, inclusion: { in: BOOKING_MODES }
    validates :interval_minutes, inclusion: { in: INTERVAL_OPTIONS }, if: :scheduled?

    def scheduled?
      booking_mode == "scheduled"
    end

    # Returns each valid appointment start within the service range.
    # ESSENTIAL: The end time closes the attendance range and is never offered as a start.
    def appointment_times
      return [] unless scheduled? && date.present? && start_time.present? && end_time.present? && interval_minutes.present?

      cursor = Time.zone.local(date.year, date.month, date.day, start_time.hour, start_time.min)
      finish = Time.zone.local(date.year, date.month, date.day, end_time.hour, end_time.min)
      times = []
      while cursor < finish
        times << cursor
        cursor += interval_minutes.minutes
      end
      times
    end

    def active_appointments
      appointments.where.not(status: %w[cancelado remarcado])
    end

    def occupied_appointment_times
      active_appointments.where.not(scheduled_at: nil).pluck(:scheduled_at)
    end

    def available_appointment_times
      occupied = occupied_appointment_times.map { |time| time.change(sec: 0) }.to_set
      appointment_times.reject { |time| occupied.include?(time.change(sec: 0)) }
    end

    def available_start_times(required_slots: 1)
      available = available_appointment_times
      appointment_times.select do |time|
        sequence = appointment_times.drop_while { |candidate| candidate < time }.first(required_slots)
        sequence.size == required_slots &&
          sequence.all? { |candidate| available.any? { |free| free.change(sec: 0) == candidate.change(sec: 0) } }
      end
    end
  end
end
