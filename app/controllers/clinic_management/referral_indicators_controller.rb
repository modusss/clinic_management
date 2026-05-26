# frozen_string_literal: true

module ClinicManagement
  # Referral indicators CRUD inside clinic Tailwind layout (Apenas Clínica mode).
  # ESSENTIAL: Mirrors host ReferralsController without Materialize layout.
  class ReferralIndicatorsController < ApplicationController
    include CommissionsHelper

    before_action :require_referral_indicators_feature!
    before_action :set_referral, only: [:edit, :update, :payment_history, :set_all_commissions_as_paid]

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

      old_commission_type = @referral.commission_type
      old_percentage = @referral.percentage

      if @referral.update(referral_params)
        type_changed = old_commission_type != @referral.commission_type
        percentage_changed = old_percentage != @referral.percentage

        if @referral.commission_type == "percentage" && (type_changed || percentage_changed)
          migrate_commissions_to_percentage(@referral)
        elsif @referral.commission_type == "fixed" && type_changed
          reset_commissions_to_fixed(@referral)
        end

        if params[:membership_role].present? && @referral.membership.present?
          @referral.membership.update(role: params[:membership_role])
        end

        redirect_to referral_indicators_path, notice: "Indicador atualizado com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # GET /clinic_management/indicadores/:id/historico
    def payment_history
      @pending_commissions = commission_status_count(@referral, "PENDING")
      @paid_commissions = commission_status_count(@referral, "PAID")
      @waiting_commissions = commission_status_count(@referral, "WAITING")
      @payment_histories = @referral.commission_payment_histories.order(payment_date: :desc).page(params[:page]).per(20)
    end

    # PUT /clinic_management/indicadores/:id/marcar-todas-pagas
    def set_all_commissions_as_paid
      commissions = @referral.dashboard_commissions.where(status: "PENDING")

      commissions.each do |commission|
        CommissionPaymentHistory.create!(
          referral: commission.referral,
          customer_name: commission.order.customer.name,
          order_number: commission.order.os,
          quantity: commission.quantity,
          payment_date: Time.current
        )
      end

      commissions.update_all(status: "PAID", payment_date: Time.current)
      redirect_to commissions_referral_indicator_path(@referral, status: "PENDING"), notice: "Comissões marcadas como pagas."
    end

    private

    def set_referral
      @referral = Referral.find(params[:id])
    end

    def referral_params
      params.require(:referral).permit(
        :name, :phone, :commission_type, :percentage,
        :can_access_leads, :is_exam_scheduler, :can_connect_whatsapp
      )
    end

    def commission_status_count(referral, status)
      referral.dashboard_commissions.where(status: status).sum(:quantity)
    end

    # ESSENTIAL: Host ApplicationController defines this; duplicated guard for isolated engine.
    def require_referral_indicators_feature!
      return if current_account&.referral_indicators_enabled?

      redirect_to clinic_management.index_today_path, alert: "Indicadores comissionados não estão habilitados para esta conta."
    end
  end
end
