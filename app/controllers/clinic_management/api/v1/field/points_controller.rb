# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        # GPS point listing and batch upload for a shift.
        class PointsController < BaseController
          before_action :set_shift

          # GET /clinic_management/api/v1/field/shifts/:shift_id/points
          def index
            points = @shift.field_track_points.chronological.limit(point_limit)
            render json: {
              points: points.map do |point|
                {
                  client_point_id: point.client_point_id,
                  recorded_at: point.recorded_at.iso8601,
                  latitude: point.latitude.to_f,
                  longitude: point.longitude.to_f,
                  accuracy_meters: point.accuracy_meters&.to_f,
                  speed_mps: point.speed_mps&.to_f,
                  bearing: point.bearing&.to_f
                }
              end
            }
          end

          # POST /clinic_management/api/v1/field/shifts/:shift_id/points/batch
          def batch
            result = ClinicManagement::FieldTracking::PointsBatchIngestion.call(
              shift: @shift,
              points: params[:points]
            )
            render json: result, status: :ok
          rescue ClinicManagement::FieldTracking::PointsBatchIngestion::Error => e
            render json: { error: e.code }, status: :unprocessable_entity
          end

          private

          def set_shift
            @shift = ClinicManagement::FieldShift.for_referral(current_field_referral.id).find(params[:shift_id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: "shift_not_found" }, status: :not_found
          end

          def point_limit
            limit = params[:limit].to_i
            return 500 if limit <= 0

            [limit, 2000].min
          end
        end
      end
    end
  end
end
