# frozen_string_literal: true

require "digest"
require "uri"

module ClinicManagement
  class LpvozConnection < ApplicationRecord
    self.table_name = "clinic_management_lpvoz_connections"

    PERMISSIONS = %w[patient_context availability reschedule].freeze

    encrypts :shared_secret

    belongs_to :account, class_name: "::Account"
    has_many :lpvoz_operations, dependent: :restrict_with_error
    has_many :lpvoz_events, dependent: :restrict_with_error
    has_many :lpvoz_call_programs, dependent: :restrict_with_error

    enum :status, { pending: "pending", active: "active", revoked: "revoked" },
         default: :pending,
         validate: true

    validates :agent_key, presence: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :installation_public_id, uniqueness: true, allow_nil: true
    validate :permissions_are_supported
    validate :lpvoz_base_url_is_safe, if: -> { lpvoz_base_url.present? }

    def generate_pairing_code!
      code = "LPVZ-#{SecureRandom.alphanumeric(4).upcase}-#{SecureRandom.alphanumeric(4).upcase}"
      update!(
        status: :pending,
        pairing_code_digest: self.class.digest(code),
        pairing_expires_at: 10.minutes.from_now,
        pairing_used_at: nil,
        installation_public_id: nil,
        shared_secret: SecureRandom.urlsafe_base64(48),
        permissions: PERMISSIONS,
        connected_at: nil,
        revoked_at: nil
      )
      code
    end

    def exchange_pairing!(code:, installation_public_id:, lpvoz_base_url:, agent_key:)
      with_lock do
        unless pairing_valid?(code)
          errors.add(:pairing_code_digest, "código temporário inválido ou expirado")
          raise ActiveRecord::RecordInvalid.new(self)
        end

        update!(
          status: :active,
          installation_public_id:,
          lpvoz_base_url:,
          agent_key:,
          pairing_used_at: Time.current,
          connected_at: Time.current,
          revoked_at: nil
        )
      end
      self
    end

    def revoke!
      update!(
        status: :revoked,
        revoked_at: Time.current,
        pairing_code_digest: nil,
        pairing_expires_at: nil,
        shared_secret: nil
      )
    end

    def allows?(permission)
      active? && permissions.include?(permission.to_s)
    end

    def pairing_valid?(code)
      return false if pairing_code_digest.blank? || pairing_expires_at.blank? || pairing_expires_at.past? || pairing_used_at.present?

      ActiveSupport::SecurityUtils.secure_compare(pairing_code_digest, self.class.digest(code))
    end

    def self.digest(value)
      Digest::SHA256.hexdigest(value.to_s.strip.upcase)
    end

    private

    def permissions_are_supported
      return if permissions.is_a?(Array) && permissions.all? { |permission| permission.in?(PERMISSIONS) }

      errors.add(:permissions, "contém uma permissão não suportada")
    end

    def lpvoz_base_url_is_safe
      uri = URI.parse(lpvoz_base_url.to_s)
      local_development = Rails.env.development? && uri.is_a?(URI::HTTP) && uri.host.in?(%w[localhost 127.0.0.1])
      return if uri.userinfo.blank? && ((uri.is_a?(URI::HTTPS) && uri.host.present?) || local_development)

      errors.add(:lpvoz_base_url, "precisa usar HTTPS e não pode conter credenciais")
    rescue URI::InvalidURIError
      errors.add(:lpvoz_base_url, "não é válida")
    end
  end
end
