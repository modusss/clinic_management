# frozen_string_literal: true

module ClinicManagement
  module Api
    module Lpvoz
      module V1
        class OperationsController < BaseController
          def context
            require_permission!("patient_context")
            return if performed?

            appointment = operation.appointment
            render json: {
              operation_reference: operation.public_id,
              patient: {
                display_name: appointment.invitation.patient_name.presence || operation.lead.name,
                responsible_name: operation.lead.name
              },
              identity_confirmation_required: true,
              missed_appointment: {
                appointment_reference: appointment.id.to_s,
                date: appointment.service.date.iso8601,
                time: appointment.effective_start_time&.strftime("%H:%M"),
                service_type: appointment.service.service_type&.name,
                location: appointment.service.service_location&.name || "Interno"
              }.compact
            }
          end

          def availability
            require_permission!("availability")
            return if performed?

            source = operation.appointment.service
            from = parse_date(params[:from]) || Date.current
            to = parse_date(params[:to]) || (from + 13.days)
            raise ArgumentError, "Período de agenda inválido." if to < from || (to - from).to_i > 31

            scope = ClinicManagement::Service.upcoming
              .where(date: from..to, service_location_id: source.service_location_id)
            scope = scope.where(service_type_id: source.service_type_id) if source.service_type_id.present?
            services = scope.includes(:appointments, :service_location, :service_type).order(:date, :start_time)
            slots = ClinicManagement::Lpvoz::AvailabilitySlots.new(services:).call

            render json: { operation_reference: operation.public_id, slots: }
          rescue ArgumentError, Date::Error => error
            render json: { error: error.message }, status: :unprocessable_entity
          end

          def reschedule
            require_permission!("reschedule")
            return if performed?
            unless ActiveModel::Type::Boolean.new.cast(params[:confirmation_verified])
              return render json: { error: "A confirmação verbal explícita é obrigatória." }, status: :unprocessable_entity
            end

            idempotency_key = request.headers["Idempotency-Key"].presence || params.require(:confirmation_token)
            result = ClinicManagement::Lpvoz::AppointmentRescheduler.new(
              operation:,
              service_id: params.require(:service_id),
              scheduled_at: params.require(:scheduled_at),
              idempotency_key:
            ).call
            appointment = result.appointment
            operation.update!(
              status: :completed,
              completed_at: Time.current,
              result: operation.result.merge(
                "rescheduled" => true,
                "new_appointment_id" => appointment.id,
                "scheduled_at" => appointment.scheduled_at&.iso8601,
                "confirmation_verified" => true,
                "confirmation_recorded_at" => Time.current.iso8601
              )
            )
            render json: {
              status: "rescheduled",
              created: result.created,
              appointment_reference: appointment.id.to_s,
              scheduled_at: appointment.scheduled_at&.iso8601,
              location: appointment.service.service_location&.name || "Interno"
            }, status: result.created ? :created : :ok
          rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound,
                 ClinicManagement::Lpvoz::AppointmentRescheduler::InvalidRequest,
                 ClinicManagement::AppointmentBooking::UnavailableTime => error
            render json: { error: error.message }, status: :unprocessable_entity
          end

          private

          def parse_date(value)
            Date.iso8601(value.to_s) if value.present?
          end
        end
      end
    end
  end
end
