# frozen_string_literal: true

module ClinicManagement
  # ServiceLocation represents an external attendance location.
  # Internal (default) uses NULL service_location_id - no record needed.
  # Each external location (e.g. "Ótica Centro", "Atendimento Shopping") = 1 record.
  #
  # ESSENTIAL: Region (existing) is for Invitation/referral mapping - intact.
  # ServiceLocation is for attendance location (internal vs external).
  class ServiceLocation < ApplicationRecord
    self.table_name = "clinic_management_service_locations"

    has_many :time_slots, dependent: :nullify
    has_many :services, dependent: :nullify
    has_many :service_location_referrals, dependent: :destroy, class_name: "ClinicManagement::ServiceLocationReferral"
    has_many :referrals, through: :service_location_referrals, source: :referral

    validates :name, presence: true
  end
end
