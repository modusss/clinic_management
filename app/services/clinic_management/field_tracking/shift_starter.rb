# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Starts a new active field shift for a captador.
    class ShiftStarter
      class Error < StandardError
        attr_reader :code

        def initialize(code, message = code)
          @code = code
          super(message)
        end
      end

      # @param referral [Referral]
      # @param user [User]
      # @param device_metadata [Hash]
      # @return [ClinicManagement::FieldShift]
      def self.call(referral:, user:, device_metadata: {})
        new(referral: referral, user: user, device_metadata: device_metadata).call
      end

      def initialize(referral:, user:, device_metadata: {})
        @referral = referral
        @user = user
        @device_metadata = device_metadata.presence || {}
      end

      def call
        if ClinicManagement::FieldShift.active.exists?(referral_id: @referral.id)
          raise Error.new("shift_already_active")
        end

        ClinicManagement::FieldShift.create!(
          referral: @referral,
          user: @user,
          status: "active",
          started_at: Time.current,
          device_metadata: @device_metadata
        )
      end
    end
  end
end
