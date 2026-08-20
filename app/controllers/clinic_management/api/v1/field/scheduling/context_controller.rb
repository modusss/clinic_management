# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        module Scheduling
          # Options required to render the mobile scheduling filters and form.
          class ContextController < BaseController
            def show
              render json: {
                locations: locations_json,
                service_types: ClinicManagement::ServiceType.where(removed: [false, nil]).order(:name).map { |type| { id: type.id, name: type.name } },
                regions: ClinicManagement::Region.active.order(:name).map { |region| { id: region.id, name: region.name } },
                permissions: {
                  can_access_leads: current_field_referral.can_access_leads?,
                  can_overbook: true
                }
              }
            end

            private

            def locations_json
              [{ id: "internal", name: "Interno" }] + scheduling_policy.allowed_locations.map do |location|
                { id: location.id.to_s, name: location.name }
              end
            end
          end
        end
      end
    end
  end
end
