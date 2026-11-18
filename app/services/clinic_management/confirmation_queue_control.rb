# frozen_string_literal: true

module ClinicManagement
  # Reports/cancels *unsent* confirmation work for the appointments visible on
  # a clinic date/location page. Never touches reminders, recoveries, other
  # dates, or another location. Legacy waves have no manual/cron distinction,
  # so cancellation intentionally includes both kinds for this date/location.
  class ConfirmationQueueControl
    SEND_JOB_CLASSES = %w[SendAppointmentMessageJob SendAppointmentMetaMessageJob].freeze
    SOURCE_JOB = "ConfirmationAppointmentJob"

    def initialize(service_date:, service_location_id:)
      @service_date = service_date
      @service_location_id = service_location_id
    end

    def status
      scope = confirmation_sends
      queued = cancellable(scope)
      {
        pending: scope.count,
        queued: queued.count,
        running: scope.where.not(id: queued.select(:id)).count,
        scheduled_for_later: queued.where("scheduled_at > ?", Time.current).count
      }
    end

    # Only removes jobs not yet claimed by a worker. A started API request may
    # still finish; no sent/tracking fields are modified.
    # Reject while an orchestrator is outstanding: it could replenish the queue.
    def cancel!
      return { blocked: true, cancelled: 0 } if outstanding_orchestrator?

      cancelled = 0
      GoodJob::Job.transaction do
        ids = cancellable(confirmation_sends)
          .lock("FOR UPDATE SKIP LOCKED")
          .pluck(:id)
        cancelled = GoodJob::Job.unscoped.where(id: ids).delete_all if ids.any?
      end

      Rails.logger.info("[ConfirmationQueueControl] cancelled=#{cancelled} date=#{@service_date} location=#{@service_location_id.inspect}")
      { blocked: false, cancelled: cancelled }
    end

    private

    def confirmation_sends
      ids = ClinicManagement::Appointment.where(
        service_id: ClinicManagement::Service.for_location(@service_location_id)
          .where(date: @service_date).select(:id)
      ).pluck(:id).map(&:to_s)

      return GoodJob::Job.none if ids.empty?

      GoodJob::Job.unscoped.where(job_class: SEND_JOB_CLASSES, finished_at: nil)
        .where("serialized_params #>> '{arguments,0,source_job}' = ?", SOURCE_JOB)
        .where("serialized_params #>> '{arguments,0,appointment_id}' IN (?)", ids)
    end

    def cancellable(scope)
      scope.where(locked_by_id: nil, performed_at: nil)
    end

    def outstanding_orchestrator?
      # The orchestrator processes all locations; it cannot safely be cancelled
      # by a location-scoped action, nor can we guarantee a stable queue while it
      # is still pending. This is conservative by design.
      GoodJob::Job.unscoped.where(job_class: SOURCE_JOB, finished_at: nil).exists?
    end
  end
end
