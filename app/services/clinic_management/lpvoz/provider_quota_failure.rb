# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class ProviderQuotaFailure
      PATTERN = %r{
        \bhttp\s*402\b|
        insufficient[_\s-]*(?:credits?|quota)|
        credits?\s+balance|
        quota[_\s-]*limit|
        quota.{0,40}(?:exceed|exhaust)|
        exceed.{0,40}quota|
        billing.{0,30}(?:limit|hard)|
        payment\s+required|
        saldo.{0,30}insuficiente|
        cr[eé]ditos?.{0,30}(?:esgot|insuficient)|
        cota.{0,30}(?:esgot|exced)
      }ix

      PROVIDER_LABELS = {
        "cartesia" => "Cartesia",
        "elevenlabs" => "ElevenLabs",
        "openai" => "OpenAI"
      }.freeze

      def self.detected?(data)
        return true if data["failure_code"] == "provider_quota_exceeded"

        candidates(data).any? { |value| value.to_s.match?(PATTERN) }
      end

      def self.provider_label(data)
        provider = data["provider"] || data.dig("collected_data", "provider")
        if provider.blank?
          text = candidates(data).join(" ")
          if text.match?(/elevenlabs/i)
            provider = "elevenlabs"
          elsif text.match?(/cartesia/i)
            provider = "cartesia"
          elsif text.match?(/openai/i)
            provider = "openai"
          end
        end
        PROVIDER_LABELS.fetch(provider.to_s.downcase, "provedor de voz")
      end

      def self.candidates(data)
        [
          data["failure_reason"],
          data["summary"],
          data.dig("collected_data", "failure_reason"),
          data.dig("collected_data", "termination_reason")
        ].compact
      end
      private_class_method :candidates
    end
  end
end
