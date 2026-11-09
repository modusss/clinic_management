# frozen_string_literal: true

module ClinicManagement
  module ServiceStatistics
    # Net receipts for a set of active orders, including payments made after the
    # original examination. Four bounded/batched lookups replace per-order queries.
    class ReceiptsByOrder
      def self.call(order_ids)
        ids = order_ids.uniq
        return {} if ids.empty?

        paid = FinancialMetrics::PAID_STATUSES
        totals = Hash.new { |hash, id| hash[id] = 0.to_d }

        EarlyPayment.where(order_id: ids, status: paid).group(:order_id).sum(:amount).each do |id, amount|
          totals[id] += amount.to_d
        end
        PickupPayment.where(order_id: ids, status: paid).group(:order_id).sum(:amount).each do |id, amount|
          totals[id] += amount.to_d
        end
        Installment.joins(:payment_book)
                   .where(payment_books: { order_id: ids }, installments: { status: paid })
                   .group("payment_books.order_id")
                   .sum("COALESCE(installments.paid_amount, installments.amount)").each do |id, amount|
          totals[id] += amount.to_d
        end

        # De-duplicate cashflow/order links just as FinancialMetrics previously
        # did using an IN subquery. One refund belongs to one order cohort.
        links = CashflowOrder.where(order_id: ids).pluck(:order_id, :cashflow_id).uniq
        unless links.empty?
          refunds = Cashflow.where(id: links.map(&:last).uniq, flow_type: "out")
                            .where.not(original_cashflow_id: nil).pluck(:id, :amount).to_h
          links.each { |order_id, cashflow_id| totals[order_id] -= refunds.fetch(cashflow_id, 0).to_d }
        end

        totals
      end
    end
  end
end
