# frozen_string_literal: true

require "test_helper"

class ClinicManagement::Lpvoz::ProviderQuotaFailureTest < Minitest::Test
  def test_detecta_o_codigo_normalizado_de_cota_da_cartesia
    data = {
      "failure_code" => "provider_quota_exceeded",
      "provider" => "cartesia",
      "failure_reason" => "Cartesia TTS recusou com HTTP 402"
    }

    assert ClinicManagement::Lpvoz::ProviderQuotaFailure.detected?(data)
    assert_equal "Cartesia", ClinicManagement::Lpvoz::ProviderQuotaFailure.provider_label(data)
  end

  def test_detecta_mensagens_legadas_de_cota_de_qualquer_provedor
    data = { "failure_reason" => "You exceeded your current quota", "provider" => "openai" }

    assert ClinicManagement::Lpvoz::ProviderQuotaFailure.detected?(data)
    assert_equal "OpenAI", ClinicManagement::Lpvoz::ProviderQuotaFailure.provider_label(data)
  end

  def test_nao_pausa_por_rate_limit_temporario
    data = { "failure_reason" => "HTTP 429 rate limit exceeded", "provider" => "cartesia" }

    refute ClinicManagement::Lpvoz::ProviderQuotaFailure.detected?(data)
  end
end
