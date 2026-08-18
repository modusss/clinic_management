# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        # Base API controller for captador field-tracking mobile clients.
        class BaseController < ActionController::API
          include ClinicManagement::FieldTrackingAuthentication
          include ClinicManagement::FieldTrackingFeatureGate
        end
      end
    end
  end
end
