module ClinicManagement
  # Links a recurring clinical time range to one explicitly supported service type.
  class TimeSlotServiceType < ApplicationRecord
    belongs_to :time_slot, class_name: "ClinicManagement::TimeSlot"
    belongs_to :service_type, class_name: "ClinicManagement::ServiceType"

    validates :service_type_id, uniqueness: { scope: :time_slot_id }
  end
end
