# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        # Login/logout for field-tracking mobile app (captadores only).
        class AuthController < BaseController
          skip_before_action :authenticate_field_mobile_token!, only: :login
          skip_before_action :require_field_tracking_features!, only: :login

          # POST /clinic_management/api/v1/field/auth/login
          def login
            result = ClinicManagement::FieldTracking::AuthLogin.call(
              email: params[:email],
              password: params[:password],
              device_label: params[:device_label],
              platform: params[:platform]
            )

            render json: {
              token: result[:token],
              referral: {
                id: result[:referral].id,
                name: result[:referral].name,
                code: result[:referral].code
              },
              user: {
                id: result[:user].id,
                name: result[:user].name,
                email: result[:user].email
              }
            }, status: :ok
          rescue ClinicManagement::FieldTracking::AuthLogin::Error => e
            render json: { error: e.code }, status: :unauthorized
          end

          # DELETE /clinic_management/api/v1/field/auth/logout
          def logout
            current_field_mobile_token.revoke!
            head :no_content
          end

          private

          def skip_field_auth?
            action_name == "login"
          end
        end
      end
    end
  end
end
