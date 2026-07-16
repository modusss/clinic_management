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

  end
end
