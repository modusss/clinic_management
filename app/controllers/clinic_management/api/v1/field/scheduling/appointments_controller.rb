# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        module Scheduling
          # Captador-owned appointment history, creation and rescheduling endpoints.
          class AppointmentsController < BaseController
            before_action :set_appointment, only: [:show, :reschedule]

            def index
              scope = scheduling_policy.appointment_scope.includes(:lead, invitation: :region, service: [:service_type, :service_location])
              scope = scope.where(status: params[:status]) if params[:status].present?
              scope = apply_search(scope)
              scope = apply_period(scope)
              appointments = scope
                .joins(:service)
                .order("clinic_management_services.date DESC, clinic_management_appointments.id DESC")
                .limit(300)

              render json: { appointments: appointments.map { |appointment| serialize(appointment) } }
            end

            def show
              render json: { appointment: serialize(@appointment) }
            end

            def create
              result = ClinicManagement::FieldScheduling::MobileAppointmentBooking.new(
                policy: scheduling_policy,
                attributes: appointment_attributes
              ).call

              render json: { appointment: serialize(result.appointment) }, status: result.created ? :created : :ok
            end

            def reschedule
              result = ClinicManagement::FieldScheduling::MobileAppointmentRescheduler.new(
                policy: scheduling_policy,
                appointment: @appointment,
                attributes: reschedule_attributes
              ).call

              render json: { appointment: serialize(result.appointment) }, status: result.created ? :created : :ok
            end

            private

            def set_appointment
              @appointment = scheduling_policy.appointment_scope.find(params[:id])
            end

            def appointment_attributes
              params.except(:appointment).permit(
                :client_request_id,
                :service_id,
                :scheduled_at,
                :allow_overbooking,
                patient: [:lead_id, :patient_name, :responsible_name, :phone, :address, :region_id, :notes]
              )
            end

            def reschedule_attributes
              params.except(:appointment).permit(:client_request_id, :service_id, :scheduled_at, :allow_overbooking)
            end

            def apply_search(scope)
              query = params[:query].to_s.strip
              return scope if query.blank?

              digits = query.gsub(/\D/, "")
              scope.joins(:lead, :invitation).where(
                "clinic_management_invitations.patient_name ILIKE :query OR clinic_management_leads.name ILIKE :query OR clinic_management_leads.phone LIKE :phone",
                query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%",
                phone: "%#{ActiveRecord::Base.sanitize_sql_like(digits)}%"
              )
            end

            def apply_period(scope)
              from = Date.iso8601(params[:from]) if params[:from].present?
              to = Date.iso8601(params[:to]) if params[:to].present?
              return scope unless from || to

              scope.joins(:service).where(clinic_management_services: { date: (from || Date.new(2000, 1, 1))..(to || Date.current + 10.years) })
            rescue Date::Error
              raise ClinicManagement::FieldScheduling::AvailabilityQuery::InvalidPeriod, "Data de filtro inválida."
            end

            def serialize(appointment)
              ClinicManagement::FieldScheduling::AppointmentJsonBuilder.call(appointment)
            end
          end
        end
      end
    end
  end
end
