module ClinicManagement
  module TimeSlotsHelper

    def next_30_days_time_slots
      week_days = {
        1 => 'Domingo',
        2 => 'Segunda-feira',
        3 => 'Terça-feira',
        4 => 'Quarta-feira',
        5 => 'Quinta-feira',
        6 => 'Sexta-feira',
        7 => 'Sábado'
      }
    
      time_slots = ClinicManagement::TimeSlot.all
      next_30_days = (Date.today..Date.today + 29.days)
    
      options = next_30_days.flat_map do |date|
        weekday = date.wday == 6 ? 7 : date.wday + 1  # ajuste aqui para fazer a correspondência correta
        weekday_slots = time_slots.select { |slot| slot.weekday == weekday }
        weekday_slots.map do |slot|
          next if Service.exists?(
            weekday: slot.weekday,
            date: date,
            start_time: slot.start_time
          )
          display_info = "#{date.strftime('%d/%m/%Y')} - #{week_days[slot.weekday]} - #{slot.start_time.strftime('%H:%M')} até #{slot.end_time.strftime('%H:%M')}"
          value = {time_slot_id: slot.id, date: date}.to_json
          [display_info, value]
        end
      end.compact
    
      {type: 'select', selected: "", input: :time_slot_id, name: 'Dias e horários disponíveis', options: options}
    end
    

  end
end
