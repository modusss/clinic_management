# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        module Scheduling
          # Real-time mobile availability for one date period and allowed location.
          class AvailabilityController < BaseController
            def index
              services = ClinicManagement::FieldScheduling::AvailabilityQuery.new(
                policy: scheduling_policy,
                from: params[:from],
                to: params[:to],
                location_id: params[:service_location_id],
                service_type_id: params[:service_type_id]
              ).call

              render json: { services: services, refreshed_at: Time.current.iso8601 }
            end

            def show
              service = scheduling_policy.service_scope
                .includes(:service_type, :service_location, :appointments)
                .find(params[:id])
              render json: {
                service: ClinicManagement::FieldScheduling::ServiceAvailabilityJsonBuilder.call(service),
                refreshed_at: Time.current.iso8601
              }
            end
          end
        end
      end
    end
  end
end
