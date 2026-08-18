# frozen_string_literal: true

module ClinicManagement
  # Records LGPD consent when a captador accepts location tracking in the mobile app.
  class FieldTrackingConsent < ApplicationRecord
    self.table_name = "clinic_management_field_tracking_consents"

    belongs_to :user, class_name: "::User"

    validates :user_id, uniqueness: true
    validates :accepted_at, presence: true
    validates :platform, presence: true
  end
end
