# frozen_string_literal: true

module ClinicManagement
  # ESSENTIAL: Requires field_tracking_enabled and clinic_module_enabled on the captador account.
  module FieldTrackingFeatureGate
    extend ActiveSupport::Concern

    included do
      before_action :require_field_tracking_features!, unless: :skip_field_auth?
    end

    private

    def require_field_tracking_features!
      account = @current_field_account
      unless account&.field_tracking_enabled? && account.clinic_module_enabled?
        render json: { error: "field_tracking_disabled" }, status: :forbidden
      end
    end
  end
end
