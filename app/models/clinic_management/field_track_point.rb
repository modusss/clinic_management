# frozen_string_literal: true

module ClinicManagement
  # ESSENTIAL: Single GPS sample uploaded from the mobile app during an active shift.
  class FieldTrackPoint < ApplicationRecord
    self.table_name = "clinic_management_field_track_points"

    belongs_to :field_shift,
               class_name: "ClinicManagement::FieldShift",
               inverse_of: :field_track_points

    validates :client_point_id, presence: true, uniqueness: { scope: :field_shift_id }
    validates :recorded_at, presence: true
    validates :latitude, :longitude, presence: true

    scope :chronological, -> { order(recorded_at: :asc) }
  end
end
