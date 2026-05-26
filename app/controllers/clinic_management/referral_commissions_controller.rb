# frozen_string_literal: true

module ClinicManagement
  # Referral commissions dashboard inside clinic layout (Apenas Clínica mode).
  # ESSENTIAL: Mirrors host CommissionsController commission actions blocked by RetailModule.
  class ReferralCommissionsController < ApplicationController
    include CommissionsHelper

    before_action :require_referral_indicators_feature!
    before_action :set_referral

    # GET /clinic_management/indicadores/:id/comissoes
    def show
      @pending_commissions = commission_status_count("PENDING")
      @paid_commissions = commission_status_count("PAID")
      @waiting_commissions = commission_status_count("WAITING")

      if @referral.commission_type == "percentage"
        all_commissions = @referral.commissions
        not_fully_received = all_commissions.where(
          "NOT (COALESCE(commission_paid_amount, 0) >= COALESCE(commission_total_amount, 0) " \
          "AND (COALESCE(commission_total_amount, 0) > 0 OR commissions.status = 'PAID'))"
        )
        @total_to_receive = not_fully_received.joins(:order).sum(Arel.sql(effective_available_sql))
        @total_received = all_commissions.sum(:commission_paid_amount)
        @total_pending = all_commissions.sum(:commission_blocked_amount)
        @total_commission = all_commissions.sum(:commission_total_amount)
        @commissions_count_all = all_commissions.count
      else
        status = params[:status] || "PENDING"
        @commissions = @referral.dashboard_commissions.where(status: status)
        @commissions_count = @commissions.count
        @commissions = @commissions.page(params[:page]).per(100)
      end
    end

    # GET /clinic_management/indicadores/:id/comissoes/cards
    def cards
      all_commissions = @referral.commissions
      @commissions_count_all = all_commissions.count
      @status_counts = calculate_status_counts(all_commissions)
      @commissions = all_commissions.order(created_at: :desc).page(params[:page]).per(50)
      @all_commissions = @commissions
      render :cards
    end

    # GET /clinic_management/indicadores/:id/pagamentos
    def payouts
      @commission_payouts = @referral.commission_payouts.order(created_at: :desc).page(params[:page]).per(30)
    end

    # PUT /clinic_management/indicadores/:id/comissoes/receber-todas
    def receive_all
      commissions = @referral.commissions.includes(:order).select do |commission|
        effective_commission_available_amount(commission).positive?
      end

      if commissions.present?
        payout = @referral.commission_payouts.create(
          total_amount: commissions.sum { |c| effective_commission_available_amount(c) }
        )
        commissions.each do |commission|
          payable = effective_commission_available_amount(commission)
          next unless payable.positive?

          payment = commission.commission_payments.create!(
            paid_amount: payable,
            paid_at: Time.current,
            commission_payout_id: payout.id
          )
          update_payment_on_commission(commission, payment)
        end
        redirect_to commissions_referral_indicator_path(@referral), notice: "Comissões pagas."
      else
        redirect_to commissions_referral_indicator_path(@referral), alert: "Nenhuma comissão disponível para pagamento."
      end
    end

    private

    def set_referral
      @referral = Referral.find(params[:id])
    end

    def commission_status_count(status)
      @referral.dashboard_commissions.where(status: status).sum(:quantity)
    end

    def update_payment_on_commission(commission, payment)
      order_paid_amount_value = helpers.order_paid_amount(commission.order)
      commission.commission_paid_amount += payment.paid_amount
      commission.order_paid_amount = order_paid_amount_value
      commission.order_pending_payment_amount = [commission.order_total_amount.to_d - order_paid_amount_value.to_d, 0].max
      commission.commission_available_amount = helpers.calculate_commission_available(commission)
      commission.commission_blocked_amount = helpers.calculate_blocked_commission(commission)
      commission.save!
    end

    def calculate_status_counts(commissions_scope)
      sql = commissions_scope.joins(:order).select(
        "CASE
           WHEN COALESCE(commission_paid_amount, 0) >= COALESCE(commission_total_amount, 0)
                AND (COALESCE(commission_total_amount, 0) > 0 OR commissions.status = 'PAID')
           THEN 'Recebido'
           WHEN #{effective_available_sql} > 0
           THEN 'A receber'
           ELSE 'Pendente'
         END AS status_label,
         COUNT(*) AS cnt"
      ).group("status_label")

      sql.each_with_object(Hash.new(0)) do |row, counts|
        counts[row.status_label] = row.cnt
      end
    end

    def effective_available_sql
      <<~SQL.squish
        CASE
          WHEN (
            orders.delivery_status = 'DELIVERED'
            OR COALESCE(commissions.order_pending_payment_amount, 0) <= 0
            OR COALESCE(commissions.order_paid_amount, 0) >= COALESCE(commissions.order_total_amount, 0)
          )
          THEN GREATEST(
            (COALESCE(commissions.order_paid_amount, 0) * (COALESCE(commissions.percentage, 0) / 100.0))
            - COALESCE(commissions.commission_paid_amount, 0),
            0
          )
          ELSE 0
        END
      SQL
    end

    def require_referral_indicators_feature!
      return if current_account&.referral_indicators_enabled?

      redirect_to clinic_management.index_today_path, alert: "Indicadores comissionados não estão habilitados para esta conta."
    end
  end
end
