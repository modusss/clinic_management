module ClinicManagement
  # TimeSlot: template for service hours (weekday + start/end time).
  # service_location_id NULL = internal; filled = external location hours.
  class TimeSlot < ApplicationRecord
    belongs_to :service_location, optional: true, class_name: "ClinicManagement::ServiceLocation"

    before_validation :parse_time_attributes
    validate :unique_slot_per_location

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

    private

    # Parses flexible time strings (16h, 16:00, 16) to HH:mm for DB storage.
    # ESSENTIAL: Handles user input when Stimulus doesn't run (e.g. JS disabled).
    def parse_time_attributes
      self.start_time = parse_time_value(start_time) if start_time.is_a?(String) && start_time.present?
      self.end_time = parse_time_value(end_time) if end_time.is_a?(String) && end_time.present?
    end

    # @param str [String] "16h", "16:00", "16", "16:30h"
    # @return [String, nil] "HH:mm" or nil if invalid
    def parse_time_value(str)
      return nil if str.blank?
      return str unless str.is_a?(String)
      match = str.strip.match(/\A(\d{1,2})h?(?::(\d{2}))?\z/i)
      return nil unless match
      hour = match[1].to_i
      min = match[2] ? match[2].to_i : 0
      return nil if hour < 0 || hour > 23 || min < 0 || min > 59
      "#{hour.to_s.rjust(2, '0')}:#{min.to_s.rjust(2, '0')}"
    end

    def unique_slot_per_location
      return if start_time.blank? || end_time.blank?
      scope = self.class.where(weekday: weekday, start_time: start_time, end_time: end_time)
      scope = scope.where(service_location_id: service_location_id)
      scope = scope.where.not(id: id) if persisted?
      return unless scope.exists?
      errors.add(:base, "Já existe um horário idêntico para este local (#{service_location&.name || 'Interno'})")
    end
  end
end
