# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        # CRUD-like endpoints for captador field shifts (expedientes).
        class ShiftsController < BaseController
          before_action :set_shift, only: [:show, :finish]

          # GET /clinic_management/api/v1/field/shifts
          def index
            scope = ClinicManagement::FieldShift.for_referral(current_field_referral.id).recent_first
            if params[:month].present?
              month_start = Date.strptime("#{params[:month]}-01", "%Y-%m-%d") rescue nil
              if month_start
                scope = scope.where(started_at: month_start.beginning_of_day..month_start.end_of_month.end_of_day)
              end
            end

            shifts = scope.limit(50)
            render json: { shifts: shifts.map { |shift| ClinicManagement::FieldTracking::ShiftJsonBuilder.call(shift) } }
          end

          # GET /clinic_management/api/v1/field/shifts/:id
          def show
            render json: ClinicManagement::FieldTracking::ShiftJsonBuilder.call(@shift)
          end

          # POST /clinic_management/api/v1/field/shifts
          def create
            shift = ClinicManagement::FieldTracking::ShiftStarter.call(
              referral: current_field_referral,
              user: current_field_user,
              device_metadata: device_metadata_params
            )
            render json: ClinicManagement::FieldTracking::ShiftJsonBuilder.call(shift), status: :created
          rescue ClinicManagement::FieldTracking::ShiftStarter::Error => e
            render json: { error: e.code }, status: :unprocessable_entity
          end

          # POST /clinic_management/api/v1/field/shifts/:id/end
          def finish
            shift = ClinicManagement::FieldTracking::ShiftEnder.call(shift: @shift, reason: params[:reason].presence || "user")
            render json: ClinicManagement::FieldTracking::ShiftJsonBuilder.call(shift)
          rescue ClinicManagement::FieldTracking::ShiftEnder::Error => e
            render json: { error: e.code }, status: :unprocessable_entity
          end

          private

          def set_shift
            @shift = ClinicManagement::FieldShift.for_referral(current_field_referral.id).find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: "shift_not_found" }, status: :not_found
          end

          def device_metadata_params
            raw = params[:device_metadata]
            return {} unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

            h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
            h.stringify_keys.slice("platform", "model", "app_version", "os_version")
          end
        end
      end
    end
  end
end
