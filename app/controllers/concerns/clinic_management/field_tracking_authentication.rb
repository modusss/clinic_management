# frozen_string_literal: true

module ClinicManagement
  # ESSENTIAL: Bearer token auth for field-tracking mobile API controllers.
  module FieldTrackingAuthentication
    extend ActiveSupport::Concern

    included do
      before_action :authenticate_field_mobile_token!, unless: :skip_field_auth?
    end

    attr_reader :current_field_user, :current_field_membership, :current_field_referral,
                :current_field_account, :current_field_mobile_token

    private

    def skip_field_auth?
      false
    end

    def authenticate_field_mobile_token!
      raw_token = bearer_token
      @current_field_mobile_token = ClinicManagement::FieldMobileToken.authenticate(raw_token)
      unless @current_field_mobile_token
        render json: { error: "unauthorized" }, status: :unauthorized
        return
      end

      @current_field_user = @current_field_mobile_token.user
      @current_field_membership = @current_field_user.memberships.find_by(role: "referral")
      unless @current_field_membership
        render json: { error: "not_referral" }, status: :forbidden
        return
      end

      @current_field_referral = ::Referral.find_by(code: @current_field_membership.code)
      unless @current_field_referral
        render json: { error: "referral_not_found" }, status: :forbidden
        return
      end

      @current_field_account = @current_field_membership.account
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return nil unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip.presence
    end
  end
end
