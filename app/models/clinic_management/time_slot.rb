module ClinicManagement
  # TimeSlot: template for service hours (weekday + start/end time).
  # service_location_id NULL = internal; filled = external location hours.
  class TimeSlot < ApplicationRecord
    belongs_to :service_location, optional: true, class_name: "ClinicManagement::ServiceLocation"

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
