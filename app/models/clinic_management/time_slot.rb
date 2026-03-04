module ClinicManagement
  # TimeSlot: template for service hours (weekday + start/end time).
  # service_location_id NULL = internal; filled = external location hours.
  class TimeSlot < ApplicationRecord
    belongs_to :service_location, optional: true, class_name: "ClinicManagement::ServiceLocation"
  end
end
