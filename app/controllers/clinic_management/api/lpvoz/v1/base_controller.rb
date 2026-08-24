# frozen_string_literal: true

module ClinicManagement
  module Api
    module Lpvoz
      module V1
        class BaseController < ActionController::API
          before_action :authenticate_connection
          before_action :verify_signature

          private

          attr_reader :connection

          def authenticate_connection
            @connection = ClinicManagement::LpvozConnection.active.find_by(
              installation_public_id: request.headers["X-LPvoz-Installation"]
            )
            render json: { error: "Integração inválida ou revogada." }, status: :unauthorized unless connection
          end

          def verify_signature
            return unless connection

            valid = ClinicManagement::Lpvoz::Signature.valid?(
              raw_body: request.raw_post,
              timestamp: request.headers["X-LPvoz-Timestamp"],
              signature: request.headers["X-LPvoz-Signature"],
              secret: connection.shared_secret
            )
            render json: { error: "Assinatura inválida ou expirada." }, status: :unauthorized unless valid
          end

          def require_permission!(permission)
            return if connection.allows?(permission)

            render json: { error: "Permissão não concedida." }, status: :forbidden
          end

          def operation
            @operation ||= connection.lpvoz_operations.find_by!(public_id: params[:id])
          end
        end
      end
    end
  end
end
