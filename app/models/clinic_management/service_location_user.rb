# frozen_string_literal: true

module ClinicManagement
  # Join model: links ServiceLocation to User (doctors).
  # ESSENTIAL: Only users with Membership.role == "doctor" should be associated.
  # Doctors associated here can see and use this location in their "atendimento de hoje" menu.
  class ServiceLocationUser < ApplicationRecord
    self.table_name = "clinic_management_service_location_users"

    belongs_to :service_location, class_name: "ClinicManagement::ServiceLocation"
    belongs_to :user, class_name: "User"

    validates :service_location_id, uniqueness: { scope: :user_id }
  end
end
