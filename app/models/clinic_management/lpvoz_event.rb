# frozen_string_literal: true

module ClinicManagement
  class LpvozEvent < ApplicationRecord
    self.table_name = "clinic_management_lpvoz_events"

    belongs_to :account, class_name: "::Account"
    belongs_to :lpvoz_connection, class_name: "ClinicManagement::LpvozConnection"
    belongs_to :lpvoz_operation, class_name: "ClinicManagement::LpvozOperation"

    enum :status, { pending: "pending", processing: "processing", processed: "processed", failed: "failed" },
         default: :pending,
         validate: true

    validates :event_id, :event_type, presence: true
    validates :event_id, uniqueness: { scope: :lpvoz_connection_id }
    validate :tenant_associations_match

    after_create_commit -> { ClinicManagement::Lpvoz::ProcessEventJob.perform_later(id) }

    private

    def tenant_associations_match
      return if lpvoz_connection.blank? || lpvoz_operation.blank?
      return if account_id == lpvoz_connection.account_id && account_id == lpvoz_operation.account_id

      errors.add(:base, "O evento precisa pertencer à mesma conta da operação")
    end
  end
end
