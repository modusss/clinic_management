# frozen_string_literal: true

module ClinicManagement
  class LpvozOperation < ApplicationRecord
    self.table_name = "clinic_management_lpvoz_operations"

    belongs_to :account, class_name: "::Account"
    belongs_to :lpvoz_connection, class_name: "ClinicManagement::LpvozConnection"
    belongs_to :lead, class_name: "ClinicManagement::Lead"
    belongs_to :appointment, class_name: "ClinicManagement::Appointment"
    belongs_to :lpvoz_call_program,
               class_name: "ClinicManagement::LpvozCallProgram",
               optional: true
    has_many :lpvoz_events, dependent: :restrict_with_error

    enum :status, {
      queued: "queued",
      dispatching: "dispatching",
      accepted: "accepted",
      in_progress: "in_progress",
      completed: "completed",
      failed: "failed",
      needs_attention: "needs_attention",
      canceled: "canceled"
    }, default: :queued, validate: true

    before_validation :assign_public_id, on: :create
    before_validation :assign_idempotency_key, on: :create
    before_validation :assign_agent_key, on: :create
    after_update_commit :enqueue_next_program_call, if: :became_terminal_program_operation?

    validates :public_id, :idempotency_key, presence: true, uniqueness: true
    validates :agent_key, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validate :tenant_matches_connection
    validate :appointment_matches_lead

    scope :recent_first, -> { order(created_at: :desc) }

    def terminal?
      completed? || failed? || needs_attention? || canceled?
    end

    def lpvoz_detail_url
      return if voice_operation_id.blank? || lpvoz_connection.lpvoz_base_url.blank?
      return unless voice_operation_id.match?(/\A[a-zA-Z0-9_-]+\z/)

      "#{lpvoz_connection.lpvoz_base_url.delete_suffix('/')}/ligacoes/#{voice_operation_id}"
    end

    private

    def assign_public_id
      self.public_id ||= "lpo_#{SecureRandom.hex(12)}"
    end

    def assign_idempotency_key
      self.idempotency_key ||= "lpvoz:#{public_id || SecureRandom.uuid}"
    end

    def assign_agent_key
      self.agent_key ||= lpvoz_call_program&.agent_key || lpvoz_connection&.agent_key
    end

    # Continue the program as soon as the current call reaches a terminal
    # state. The minute cron remains a recovery mechanism for restarts and
    # missed callbacks, rather than the primary continuation mechanism.
    def enqueue_next_program_call
      return unless lpvoz_call_program&.active?

      ClinicManagement::Lpvoz::DispatchNextProgramCallJob
        .set(wait: 5.seconds)
        .perform_later(lpvoz_call_program_id)
    end

    def became_terminal_program_operation?
      return false if lpvoz_call_program_id.blank? || !saved_change_to_status?

      previous_status, current_status = saved_change_to_status
      current_status.in?(LpvozCallProgram::TERMINAL_OPERATION_STATUSES) &&
        !previous_status.in?(LpvozCallProgram::TERMINAL_OPERATION_STATUSES)
    end

    def tenant_matches_connection
      return if lpvoz_connection.blank? || account_id == lpvoz_connection.account_id

      errors.add(:lpvoz_connection, "precisa pertencer à mesma conta")
    end

    def appointment_matches_lead
      return if appointment.blank? || lead.blank? || appointment.lead_id == lead_id

      errors.add(:appointment, "precisa pertencer ao paciente")
    end
  end
end
