module ClinicManagement
  module ServicesHelper
    def description_service(service)
      "#{service.service_type&.name} - #{service.date.strftime("%d/%m/%Y")} - #{show_week_day(service.weekday)} (#{service.start_time.strftime("%H:%M")} - #{service.end_time.strftime("%H:%M")})"
    end

    def display_service_name(service)
      start_time = service.start_time.strftime("%H:%Mh")
      end_time = service.end_time.strftime("%H:%Mh")
      "#{show_week_day(service.weekday)}, #{service.date.strftime("%d/%m/%Y")} - #{start_time} às #{end_time}"
    end

    def available_time_slots_for_next_30_days
      # Agrupar slots de tempo por dia da semana
      time_slots = ClinicManagement::TimeSlot.all.group_by(&:weekday)
  
      # Buscar serviços existentes nos próximos 30 dias
      existing_services = ClinicManagement::Service.where(date: Date.current..Date.current + 29.days)
                                                 .pluck(:date, :start_time)
                                                 .group_by { |date, _| date }
  
      # Gerar slots disponíveis
      available_slots = []
      
      (Date.current..Date.current + 29.days).each do |date|
        weekday = date.wday == 6 ? 7 : date.wday + 1
        weekday_slots = time_slots[weekday] || []
        
        weekday_slots.each do |slot|
          # Verificar se o slot específico já está ocupado
          existing_services_for_date = existing_services[date]&.map { |_, start_time| start_time }
          next if existing_services_for_date&.include?(slot.start_time)
          
          available_slots << {
            date: date,
            time_slot: slot,
            formatted_date: I18n.l(date, format: '%A, %d/%m/%Y'),
            formatted_time: "#{slot.start_time.strftime('%H:%M')} - #{slot.end_time.strftime('%H:%M')}"
          }
        end
      end
      
      available_slots
    end
  end
end
