# frozen_string_literal: true

module ClinicManagement
  # ESSENTIAL: Web field-tracking panel — manager/owner only, account flag required.
  module FieldTrackingManagerAuthorization
    extend ActiveSupport::Concern

    included do
      before_action :authorize_field_tracking_manager!
    end

    private

    # Redirects non-managers and accounts without field tracking to staff home.
    def authorize_field_tracking_manager!
      unless helpers.is_manager_above? && field_tracking_enabled?
        redirect_to clinic_management.index_today_path,
                    alert: "Rastreamento de campo não está disponível para seu perfil ou conta."
      end
    end
  end
end
