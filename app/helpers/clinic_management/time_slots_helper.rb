module ClinicManagement
  module TimeSlotsHelper

    def time_slots_with_display_info
      ClinicManagement::TimeSlot.all.map do |time_slot|
        week_days = {
          1 => 'Domingo',
          2 => 'Segunda-feira',
          3 => 'Terça-feira',
          4 => 'Quarta-feira',
          5 => 'Quinta-feira',
          6 => 'Sexta-feira',
          7 => 'Sábado'
        }
        
        display_info = "#{week_days[time_slot.weekday]} - #{time_slot.start_time.strftime('%H:%M')} até #{time_slot.end_time.strftime('%H:%M')}"
        [display_info, time_slot.id]
      end
    end

    def show_week_day(weekday)
      case weekday
      when 1
        "Domingo"
      when 2
        "Segunda-feira"
      when 3
        "Terça-feira"
      when 4
        "Quarta-feira"
      when 5
        "Quinta-feira"
      when 6
        "Sexta-feira"
      when 7
        "Sábado"
      end
    end

  end
end
