module ClinicManagement
  module Analytics
    # Classifies the moment an active booking entered the service's agenda.
    # A same-day attendance update is not evidence of a same-day booking.
    class BookingOrigin
      LABELS = {
        advance: "Agendados antecipadamente",
        same_day: "Encaixes no dia",
        rescheduled_same_day: "Remarcados no dia",
        after_date: "Registros posteriores ao exame"
      }.freeze

      def initialize(appointments:, service_dates:, legacy_reschedules: nil)
        @appointments = appointments
        @service_dates = service_dates
        @legacy_reschedules = legacy_reschedules || load_legacy_reschedules
        @legacy_by_lead = @legacy_reschedules.group_by(&:lead_id)
      end

      # Historical replacements and cancellations are not live bookings.
      def category(appointment, service_date)
        return nil unless appointment.status == "agendado" && service_date.present?

        booking_date = appointment.created_at&.in_time_zone&.to_date
        return :after_date unless booking_date
        return :advance if booking_date < service_date
        return :after_date if booking_date > service_date

        rescheduled?(appointment) ? :rescheduled_same_day : :same_day
      end

      private

      # Older desktop remarcations omitted their explicit origin link. Match the
      # original patient's name as well as the lead (which can contain family
      # members), and require the old status update to coincide with creation.
      # Avoid treating an unrelated, much older remarcation as a new reschedule.
      def load_legacy_reschedules
        candidates = @appointments.select do |appointment|
          appointment.status == "agendado" && appointment.rescheduled_from_appointment_id.blank? &&
            appointment.created_at&.in_time_zone&.to_date == @service_dates[appointment.service_id]
        end
        lead_ids = candidates.map(&:lead_id).compact.uniq
        return [] if lead_ids.empty?

        Appointment.where(lead_id: lead_ids, status: "remarcado").includes(:invitation).to_a
      end

      def rescheduled?(appointment)
        return true if appointment.rescheduled_from_appointment_id.present?

        name = patient_name(appointment)
        return false if name.blank?

        Array(@legacy_by_lead[appointment.lead_id]).any? do |prior|
          prior.id != appointment.id && prior.created_at < appointment.created_at &&
            patient_name(prior) == name &&
            prior.updated_at.present? &&
            (prior.updated_at - appointment.created_at).abs <= 1.hour
        end
      end

      def patient_name(appointment)
        (appointment.invitation&.patient_name.presence || appointment.lead&.name).to_s
          .squish.downcase
      end
    end
  end
end
