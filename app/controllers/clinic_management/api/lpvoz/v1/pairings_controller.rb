# frozen_string_literal: true

module ClinicManagement
  module Api
    module Lpvoz
      module V1
        class PairingsController < ActionController::API
          def exchange
            code = params.require(:code).to_s.strip.upcase
            connection = ClinicManagement::LpvozConnection.pending.find_by(
              pairing_code_digest: ClinicManagement::LpvozConnection.digest(code)
            )
            return render json: { error: "Código temporário inválido ou expirado." }, status: :unprocessable_entity unless connection

            connection.exchange_pairing!(
              code:,
              installation_public_id: params.require(:installation_id),
              lpvoz_base_url: params.require(:lpvoz_base_url),
              agent_key: params.require(:agent_key)
            )
            render json: {
              external_tenant_id: connection.account_id.to_s,
              account_name: connection.account.name,
              shared_secret: connection.shared_secret,
              callback_url: api_lpvoz_v1_events_url,
              permissions: connection.permissions,
              contract_version: "2026-08-24"
            }
          rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
            render json: { error: error.message }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
