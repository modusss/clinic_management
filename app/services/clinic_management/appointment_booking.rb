# frozen_string_literal: true

module ClinicManagement
  # Creates appointments while centralizing exclusive self-booking and intentional staff overbooking.
  class AppointmentBooking
    class UnavailableTime < StandardError; end

    def initialize(service:, allow_overbooking: false)
      @service = service
      @allow_overbooking = allow_overbooking
    end

    # Reserves consecutive times for the supplied appointment attribute hashes.
    # @param appointment_attributes [Array<Hash>]
    # @param starting_at [Time, nil]
    # @return [Array<ClinicManagement::Appointment>]
    def create_consecutive!(appointment_attributes:, starting_at: nil)
      service.with_lock do
        times = resolved_times(appointment_attributes.size, starting_at)
        appointment_attributes.each_with_index.map do |attributes, index|
          scheduled_at = times[index]
          occupied = occupied?(scheduled_at)
          raise UnavailableTime, "O horário escolhido acabou de ser ocupado." if occupied && !@allow_overbooking
          intentional_overbooking = @allow_overbooking && (occupied || !configured_time?(scheduled_at))

          ClinicManagement::Appointment.create!(
            attributes.merge(
              service: service,
              scheduled_at: scheduled_at,
              overbooked: intentional_overbooking
            )
          )
        end
      end
    end

    private

    attr_reader :service

    def resolved_times(count, starting_at)
      return Array.new(count) unless service.scheduled?

      candidates = service.appointment_times
      start_index = starting_at.present? ? candidates.index { |time| same_minute?(time, starting_at) } : nil
      if @allow_overbooking && count == 1 && starting_at.present? && starting_at.to_date == service.date
        return [starting_at]
      end
      raise UnavailableTime, "Selecione um horário válido." if start_index.nil?

      selected = candidates.slice(start_index, count)
      raise UnavailableTime, "Não há horários consecutivos suficientes." unless selected&.size == count

      unless @allow_overbooking
        raise UnavailableTime, "Um dos horários consecutivos não está mais disponível." if selected.any? { |time| occupied?(time) }
      end
      selected
    end

    def occupied?(time)
      return false if time.blank?

      service.active_appointments.where(scheduled_at: time).exists?
    end

    def same_minute?(first, second)
      first.in_time_zone.change(sec: 0) == second.in_time_zone.change(sec: 0)
    end

    def configured_time?(time)
      service.appointment_times.any? { |candidate| same_minute?(candidate, time) }
    end
  end
end
