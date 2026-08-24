# frozen_string_literal: true

require "net/http"

module ClinicManagement
  module Lpvoz
    class Client
      class RequestFailed < StandardError; end

      def initialize(connection:)
        @connection = connection
      end

      def create_operation(operation)
        post(
          "/internal/v1/voice_operations",
          {
            agent_key: connection.agent_key,
            external_reference: operation.public_id,
            purpose: "missed_appointment_recovery",
            contact: {
              phone: e164(operation.lead.phone),
              display_name: operation.appointment.invitation.patient_name.presence || operation.lead.name
            },
            context: {
              operation_reference: operation.public_id,
              appointment_reference: operation.appointment_id.to_s,
              privacy_instruction: "Confirme a identidade antes de revelar dados do atendimento."
            }
          },
          "Idempotency-Key" => operation.idempotency_key
        )
      end

      private

      attr_reader :connection

      def post(path, body, extra_headers = {})
        raw_body = ActiveSupport::JSON.encode(body)
        timestamp = Time.current.iso8601
        uri = URI.join("#{connection.lpvoz_base_url.delete_suffix('/')}/", path.delete_prefix("/"))
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["X-LPvoz-Installation"] = connection.installation_public_id
        request["X-LPvoz-Timestamp"] = timestamp
        request["X-LPvoz-Signature"] = Signature.sign(raw_body:, timestamp:, secret: connection.shared_secret)
        extra_headers.each { |key, value| request[key] = value }
        request.body = raw_body

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 5,
          read_timeout: 20
        ) { |http| http.request(request) }
        parsed = ActiveSupport::JSON.decode(response.body.to_s.presence || "{}")
        raise RequestFailed, parsed["error"].presence || "LPVoz retornou HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)

        parsed
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error => error
        raise RequestFailed, "Não foi possível comunicar com o LPVoz: #{error.message}"
      end

      def e164(phone)
        digits = phone.to_s.gsub(/\D/, "")
        digits = "55#{digits}" if digits.length.in?([10, 11])
        value = "+#{digits}"
        raise RequestFailed, "Telefone do paciente inválido para ligação." unless value.match?(/\A\+[1-9]\d{7,14}\z/)

        value
      end
    end
  end
end
