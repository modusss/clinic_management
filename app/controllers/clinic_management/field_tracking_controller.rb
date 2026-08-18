# frozen_string_literal: true

module ClinicManagement
  # Web manager panel for live and historical captador GPS shifts.
  # ESSENTIAL: Referral users are blocked by ApplicationController#redirect_referral_users.
  class FieldTrackingController < ApplicationController
    include ClinicManagement::FieldTrackingManagerAuthorization

    before_action :set_shift, only: [:show]

    # GET /clinic_management/rastreamento
    # JSON format returns live snapshot for map polling.
    def index
      @active_shifts = active_shifts_scope

      respond_to do |format|
        format.html
        format.json do
          render json: ClinicManagement::FieldTracking::LiveSnapshotBuilder.call(@active_shifts)
        end
      end
    end

    # GET /clinic_management/rastreamento/historico
    def history
      @date = parse_history_date
      @referral_id = params[:referral_id].presence
      @referrals = Referral.order(:name)
      @shifts = history_shifts_scope
    end

    # GET /clinic_management/rastreamento/:id
    def show
      @points = @shift.field_track_points.chronological

      respond_to do |format|
        format.html
        format.json do
          render json: ClinicManagement::FieldTracking::ShiftJsonBuilder.call(@shift, include_points: true)
        end
      end
    end

    private

    def active_shifts_scope
      ClinicManagement::FieldShift.active
                                  .includes(:referral, :last_track_point)
                                  .recent_first
    end

    def history_shifts_scope
      scope = ClinicManagement::FieldShift
              .where(status: %w[active completed])
              .includes(:referral)
              .recent_first

      scope = scope.for_referral(@referral_id) if @referral_id.present?

      day_range = @date.beginning_of_day..@date.end_of_day
      scope.where(started_at: day_range)
    end

    def parse_history_date
      return Date.current if params[:date].blank?

      Date.parse(params[:date])
    rescue ArgumentError
      Date.current
    end

    def set_shift
      @shift = ClinicManagement::FieldShift.includes(:referral).find(params[:id])
    end
  end
end
