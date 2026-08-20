# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        module Scheduling
          # Shared authorization, policy and JSON errors for mobile scheduling.
          class BaseController < ClinicManagement::Api::V1::Field::BaseController
            before_action :require_exam_scheduler!

            rescue_from ClinicManagement::FieldScheduling::AccessPolicy::Forbidden do |error|
              render json: { error: "forbidden", message: error.message }, status: :forbidden
            end
            rescue_from ClinicManagement::FieldScheduling::AvailabilityQuery::InvalidPeriod do |error|
              render json: { error: "invalid_period", message: error.message }, status: :unprocessable_entity
            end
            rescue_from ClinicManagement::FieldScheduling::MobileAppointmentBooking::InvalidPatient do |error|
              render json: { error: "invalid_patient", message: error.message }, status: :unprocessable_entity
            end
            rescue_from ClinicManagement::FieldScheduling::MobileAppointmentRescheduler::InvalidAppointment do |error|
              render json: { error: "invalid_appointment", message: error.message }, status: :unprocessable_entity
            end
            rescue_from ClinicManagement::AppointmentBooking::UnavailableTime do |error|
              render json: { error: "unavailable_time", message: error.message }, status: :conflict
            end
            rescue_from ActiveRecord::RecordInvalid do |error|
              render json: {
                error: "validation_failed",
                message: error.record.errors.full_messages.to_sentence
              }, status: :unprocessable_entity
            end
            rescue_from ActiveRecord::RecordNotFound do
              render json: { error: "not_found", message: "Registro não encontrado." }, status: :not_found
            end

            private

            def require_exam_scheduler!
              return if current_field_referral&.is_exam_scheduler?

              render json: { error: "scheduling_disabled" }, status: :forbidden
            end

            def scheduling_policy
              @scheduling_policy ||= ClinicManagement::FieldScheduling::AccessPolicy.new(
                account: current_field_account,
                referral: current_field_referral,
                user: current_field_user
              )
            end
          end
        end
      end
    end
  end
end
