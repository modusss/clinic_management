module ClinicManagement
  module TimeSlotsHelper

    
    def next_30_days_time_slots
      # Agrupar slots de tempo por dia da semana
      time_slots = ClinicManagement::TimeSlot.all.group_by(&:weekday)
      # Buscar serviços existentes nos próximos 30 dias e agrupar por data
      dates_with_services = Service.where(date: Date.today..Date.today + 29.days)
                                   .pluck(:date)
                                   .uniq
    
      options = (Date.today..Date.today + 29.days).flat_map do |date|
        # Pular o dia se já existem serviços marcados para ele
        next if dates_with_services.include?(date)
        
        weekday = date.wday == 6 ? 7 : date.wday + 1
        weekday_slots = time_slots[weekday] || []
        weekday_slots.map do |slot|
          display_info = "#{date.strftime('%d/%m/%Y')} - #{I18n.t('date.day_names')[date.wday]} - #{slot.start_time.strftime('%H:%M')} até #{slot.end_time.strftime('%H:%M')}"
          value = {time_slot_id: slot.id, date: date}.to_json
          [display_info, value]
        end
      end.compact
    
      {type: 'select', selected: "", input: :time_slot_id, name: 'Dias e horários disponíveis', options: options}
    end
    
    
    
    

  end
end
