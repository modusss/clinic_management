# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Authenticates a captador via Devise credentials and issues a mobile bearer token.
    class AuthLogin
      class Error < StandardError
        attr_reader :code

        # @param code [String] machine-readable error key for API responses
        def initialize(code, message = code)
          @code = code
          super(message)
        end
      end

      # @param email [String]
      # @param password [String]
      # @param device_label [String, nil]
      # @param platform [String]
      # @return [Hash] :token, :referral, :user
      def self.call(email:, password:, device_label: nil, platform: "android")
        new(email: email, password: password, device_label: device_label, platform: platform).call
      end

      def initialize(email:, password:, device_label: nil, platform: "android")
        @email = email.to_s.strip.downcase
        @password = password
        @device_label = device_label
        @platform = platform.presence || "android"
      end

      def call
        user = User.find_by("LOWER(email) = ?", @email)
        raise Error.new("invalid_credentials") unless user&.valid_password?(@password)
        raise Error.new("user_inactive") unless user.active_for_authentication?

        membership = user.memberships.find_by(role: "referral")
        raise Error.new("not_referral") unless membership

        account = membership.account
        raise Error.new("field_tracking_disabled") unless account.field_tracking_enabled?
        raise Error.new("clinic_module_disabled") unless account.clinic_module_enabled?

        referral = ::Referral.find_by(code: membership.code)
        raise Error.new("referral_not_found") unless referral

        token = ClinicManagement::FieldMobileToken.issue!(
          user: user,
          device_label: @device_label,
          platform: @platform
        )

        { token: token, referral: referral, user: user, account: account }
      end
    end
  end
end
