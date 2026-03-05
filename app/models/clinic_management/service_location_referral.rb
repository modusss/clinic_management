# frozen_string_literal: true

module ClinicManagement
  # Join model: which Referrals (indicators) can use a ServiceLocation.
  # If no record exists, the referral cannot see/use that external location.
  class ServiceLocationReferral < ApplicationRecord
    self.table_name = "clinic_management_service_location_referrals"

    belongs_to :service_location, class_name: "ClinicManagement::ServiceLocation"
    belongs_to :referral, class_name: "Referral"

    validates :service_location_id, uniqueness: { scope: :referral_id }
  end
end
