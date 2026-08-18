# frozen_string_literal: true

module ClinicManagement
  # ESSENTIAL: Bearer token for field-tracking mobile API — digest only, never store plain text.
  class FieldMobileToken < ApplicationRecord
    self.table_name = "clinic_management_field_mobile_tokens"

    DEFAULT_TTL = 30.days

    belongs_to :user, class_name: "::User"

    validates :token_digest, presence: true, uniqueness: true
    validates :platform, presence: true
    validates :expires_at, presence: true

    scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

    # Issues a new bearer token for the given user.
    #
    # @param user [User]
    # @param device_label [String, nil]
    # @param platform [String] "android" or "ios"
    # @return [String] raw token (shown once to client)
    def self.issue!(user:, device_label: nil, platform: "android")
      raw_token = SecureRandom.hex(32)
      create!(
        user: user,
        token_digest: digest(raw_token),
        device_label: device_label,
        platform: platform,
        expires_at: DEFAULT_TTL.from_now
      )
      raw_token
    end

    # Resolves an active token record from the raw bearer value.
    #
    # @param raw_token [String]
    # @return [ClinicManagement::FieldMobileToken, nil]
    def self.authenticate(raw_token)
      return nil if raw_token.blank?

      record = active.find_by(token_digest: digest(raw_token))
      return nil unless record

      record.touch_last_used!
      record
    end

    # SHA-256 hex digest for storage and lookup.
    #
    # @param raw_token [String]
    # @return [String]
    def self.digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end

    # Marks token as revoked (logout).
    def revoke!
      update!(revoked_at: Time.current)
    end

    # Updates last_used_at without touching updated_at semantics heavily.
    def touch_last_used!
      update_column(:last_used_at, Time.current)
    end
  end
end
