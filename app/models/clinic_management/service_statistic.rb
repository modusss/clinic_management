module ClinicManagement
  # ESSENTIAL: Cached metrics for one clinic service (one row per service_id).
  # Remarcados are never stored — see ServiceStatistics::Policy.
  class ServiceStatistic < ApplicationRecord
    self.table_name = "clinic_management_service_statistics"

    belongs_to :service, class_name: "ClinicManagement::Service"
    belongs_to :service_location,
               class_name: "ClinicManagement::ServiceLocation",
               optional: true

    validates :service_id, uniqueness: true
    validates :service_date, presence: true
  end
end
