module ClinicManagement
  module ServicesHelper
    def description_service(service)
      # Se existe apenas um tipo de serviço ativo, não precisa mostrar o nome dele
      active_service_types_count = ClinicManagement::ServiceType.where(removed: false).count
      
      if active_service_types_count > 1
        # Múltiplos tipos: mostrar o nome do tipo
        "#{service.service_type&.name} - #{service.date.strftime("%d/%m/%Y")} - #{show_week_day(service.weekday)} (#{service.start_time.strftime("%H:%M")} - #{service.end_time.strftime("%H:%M")})"
      else
        # Apenas um tipo: omitir o nome do tipo
        "#{service.date.strftime("%d/%m/%Y")} - #{show_week_day(service.weekday)} (#{service.start_time.strftime("%H:%M")} - #{service.end_time.strftime("%H:%M")})"
      end
    end

    def display_service_name(service)
      start_time = service.start_time.strftime("%H:%Mh")
      end_time = service.end_time.strftime("%H:%Mh")
      "#{show_week_day(service.weekday)}, #{service.date.strftime("%d/%m/%Y")} - #{start_time} às #{end_time}"
    end

    def grouped_services_for_select(services_list)
      # Agrupar serviços por data
      grouped = services_list.group_by { |s| [s.date, s.weekday] }
      
      # Se houver apenas um serviço por data, não agrupar
      if grouped.all? { |_, services| services.size == 1 }
        # Retornar array simples para options_for_select
        return [false, services_list.map { |s| [description_service(s), s.id] }]
      end
      
      # Criar estrutura para grouped_options_for_select
      grouped_options = grouped.map do |(date, weekday), services|
        group_label = "#{date.strftime("%d/%m/%Y")} - #{show_week_day(weekday)}"
        # Ordenar serviços por horário de início (do mais cedo para o mais tarde)
        sorted_services = services.sort_by(&:start_time)
        options = sorted_services.map do |service|
          ["#{service.start_time.strftime("%H:%M")} - #{service.end_time.strftime("%H:%M")}", service.id]
        end
        [group_label, options]
      end
      
      [true, grouped_options]
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
