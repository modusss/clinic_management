# frozen_string_literal: true

module ClinicManagement
  # Referral indicators CRUD inside clinic Tailwind layout (Apenas Clínica mode).
  # ESSENTIAL: Index + edit only — no commission fields or dashboards (no retail orders).
  class ReferralIndicatorsController < ApplicationController
    before_action :require_referral_indicators_feature!
    before_action :set_referral, only: [:edit, :update]

    # GET /clinic_management/indicadores
    def index
      @all_referrals = Referral.all
      @active_referrals = @all_referrals.select(&:active?)
      @inactive_referrals = @all_referrals.reject(&:active?)
      @quantity = @all_referrals.count
      @active_quantity = @active_referrals.count
      @inactive_quantity = @inactive_referrals.count
    end

    # GET /clinic_management/indicadores/:id/edit
    def edit
    end

    # PATCH /clinic_management/indicadores/:id
    def update
      @referral.code = SecureRandom.hex(3) if @referral.code.blank?

      if @referral.update(referral_params)
        if params[:membership_role].present? && @referral.membership.present?
          @referral.membership.update(role: params[:membership_role])
        end

        redirect_to referral_indicators_path, notice: "Captador atualizado com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_referral
      @referral = Referral.find(params[:id])
    end

    def referral_params
      params.require(:referral).permit(
        :name, :phone,
        :can_access_leads, :is_exam_scheduler, :can_connect_whatsapp
      )
    end

    # ESSENTIAL: Host ApplicationController defines this; duplicated guard for isolated engine.
    def require_referral_indicators_feature!
      return if current_account&.referral_indicators_enabled?

      redirect_to clinic_management.index_today_path, alert: "Captadores não estão habilitados para esta conta."
    end
  end
end
