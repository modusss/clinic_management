# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        # Current captador profile and active shift snapshot.
        class MeController < BaseController
          # GET /clinic_management/api/v1/field/me
          def show
            active_shift = ClinicManagement::FieldShift.active.find_by(referral_id: current_field_referral.id)

            render json: {
              user: {
                id: current_field_user.id,
                name: current_field_user.name,
                email: current_field_user.email
              },
              referral: {
                id: current_field_referral.id,
                name: current_field_referral.name,
                code: current_field_referral.code
              },
              active_shift: active_shift ? ClinicManagement::FieldTracking::ShiftJsonBuilder.call(active_shift) : nil
            }
          end
        end
      end
    end
  end
end
