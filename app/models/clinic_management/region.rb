module ClinicManagement
  class Region < ApplicationRecord
    has_many :invitations

    # ESSENTIAL: Scope for non-deleted regions. Use in all form selects and index lists.
    # Associations (e.g. invitation.region) load without this scope to preserve historical data.
    scope :active, -> { where(deleted_at: nil) }

    # Soft delete: sets deleted_at so region disappears from lists but stays in DB for referential integrity.
    def soft_delete!
      update!(deleted_at: Time.current)
    end

    def deleted?
      deleted_at.present?
    end

    def restore!
      update!(deleted_at: nil)
    end

    # ESSENTIAL: Returns the "Local" system region (active). Finds or creates, restores if soft-deleted.
    def self.ensure_local!
      region = unscoped.find_by(name: "Local")
      if region
        region.restore! if region.deleted?
        region
      else
        create!(name: "Local")
      end
    end
  end
end
