module ClinicManagement
  module TimeSlotsHelper

    
    def next_30_days_time_slots(service = nil)
      # Verificar se o serviço existe e se a data já passou
      if service && service.date && service.date < Date.today
        display_info = "#{service.date.strftime('%d/%m/%Y')} - #{I18n.t('date.day_names')[service.date.wday]} - #{service.start_time.strftime('%H:%M')} até #{service.end_time.strftime('%H:%M')}"
        {type: 'text', value: display_info, input: :time_slot_id, name: 'Dias e horários disponíveis', disabled: true}
      else
        # Agrupar slots de tempo por dia da semana
        time_slots = ClinicManagement::TimeSlot.all.group_by(&:weekday)
    
        # Buscar serviços existentes nos próximos 30 dias, excluindo o serviço atual
        existing_services = Service.where(date: Date.today..Date.today + 29.days)
          .where.not(id: service&.id)
          .pluck(:date, :start_time)
          .group_by { |date, _| date }
    
        options = (Date.today..Date.today + 29.days).flat_map do |date|
          weekday = date.wday == 6 ? 7 : date.wday + 1
          weekday_slots = time_slots[weekday] || []
    
          weekday_slots.reject do |slot|
            # Verificar se o slot específico já está ocupado por um serviço existente
            existing_services_for_date = existing_services[date]&.map { |_, start_time| start_time }
            existing_services_for_date&.include?(slot.start_time)
          end.map do |slot|
            display_info = "#{date.strftime('%d/%m/%Y')} - #{I18n.t('date.day_names')[date.wday]} - #{slot.start_time.strftime('%H:%M')} até #{slot.end_time.strftime('%H:%M')}"
            value = {time_slot_id: slot.id, date: date}.to_json
            [display_info, value]
          end
        end.compact
    
        # Verificar se a opção específica do dia atual do serviço já existe nas opções regulares
        service_slot_exists = false
        if service && service.date && service.date >= Date.today
          slot = ClinicManagement::TimeSlot.find_by(weekday: service.date.wday == 6 ? 7 : service.date.wday + 1, start_time: service.start_time)
          if slot
            service_slot_value = {time_slot_id: slot.id, date: service.date}.to_json
            service_slot_exists = options.any? { |_, value| value == service_slot_value }
          end
        end
    
        # Adicionar a opção específica para o dia atual do serviço, se existir e não estiver presente nas opções regulares
        if service && service.date && service.date >= Date.today && !service_slot_exists
          slot = ClinicManagement::TimeSlot.find_by(weekday: service.date.wday == 6 ? 7 : service.date.wday + 1, start_time: service.start_time)
          if slot
            display_info = "#{service.date.strftime('%d/%m/%Y')} - #{I18n.t('date.day_names')[service.date.wday]} - #{service.start_time.strftime('%H:%M')} até #{service.end_time.strftime('%H:%M')}"
            value = {time_slot_id: slot.id, date: service.date}.to_json
            options.unshift([display_info, value])
          end
        end
    
        # Verificar se o serviço existe e encontrar o valor selecionado anteriormente
        selected_value = if service && service.date && service.start_time
          slot = ClinicManagement::TimeSlot.find_by(weekday: service.date.wday == 6 ? 7 : service.date.wday + 1, start_time: service.start_time)
          slot_value = {time_slot_id: slot&.id, date: service.date}.to_json
          options.find { |_, value| value == slot_value }&.last
        else
          ""
        end
    
        {type: 'select', selected: selected_value, input: :time_slot_id, name: 'Dias e horários disponíveis', options: options}
      end
    end
    
    
    

  end
end
