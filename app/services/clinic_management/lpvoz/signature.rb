# frozen_string_literal: true

require "openssl"

module ClinicManagement
  module Lpvoz
    module Signature
      MAX_AGE = 5.minutes
      module_function

      def sign(raw_body:, timestamp:, secret:)
        payload = "#{timestamp}.#{raw_body}"
        "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, payload)}"
      end

      def valid?(raw_body:, timestamp:, signature:, secret:)
        parsed_time = Time.iso8601(timestamp.to_s)
        return false if (Time.current - parsed_time).abs > MAX_AGE

        expected = sign(raw_body:, timestamp:, secret:)
        signature.present? && ActiveSupport::SecurityUtils.secure_compare(expected, signature)
      rescue ArgumentError
        false
      end
    end
  end
end
