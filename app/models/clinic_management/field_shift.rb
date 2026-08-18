# frozen_string_literal: true

module ClinicManagement
  # ESSENTIAL: One field work session (expediente) for a Referral — GPS points attach here.
  class FieldShift < ApplicationRecord
    self.table_name = "clinic_management_field_shifts"

    STATUSES = %w[active completed cancelled].freeze

    belongs_to :referral, class_name: "::Referral"
    belongs_to :user, class_name: "::User"
    has_many :field_track_points,
             class_name: "ClinicManagement::FieldTrackPoint",
             foreign_key: :field_shift_id,
             dependent: :destroy,
             inverse_of: :field_shift

    # ESSENTIAL: Latest GPS sample for live map markers (web manager panel).
    has_one :last_track_point,
            -> { order(recorded_at: :desc) },
            class_name: "ClinicManagement::FieldTrackPoint",
            foreign_key: :field_shift_id,
            inverse_of: :field_shift

    validates :status, inclusion: { in: STATUSES }
    validates :started_at, presence: true
    validate :single_active_shift_per_referral, if: -> { status == "active" }

    scope :active, -> { where(status: "active") }
    scope :completed, -> { where(status: "completed") }
    scope :for_referral, ->(referral_id) { where(referral_id: referral_id) }
    scope :recent_first, -> { order(started_at: :desc) }

    # @return [Boolean]
    def active?
      status == "active"
    end

    private

    # ESSENTIAL: At most one active expediente per captador at a time.
    def single_active_shift_per_referral
      scope = self.class.active.where(referral_id: referral_id)
      scope = scope.where.not(id: id) if persisted?
      return unless scope.exists?

      errors.add(:base, "shift_already_active")
    end
  end
end
