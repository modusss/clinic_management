module ClinicManagement
  module TimeSlotsHelper
    WEEKDAY_NAMES = { 1 => "Domingo", 2 => "Segunda-feira", 3 => "Terça-feira", 4 => "Quarta-feira", 5 => "Quinta-feira", 6 => "Sexta-feira", 7 => "Sábado" }.freeze

    def show_week_day(weekday)
      WEEKDAY_NAMES[weekday.to_i]
    end
    # Returns array of { date:, time_slot:, formatted_date:, formatted_time: } for new service form.
    # ESSENTIAL: Filters by current_service_location_id (nil = internal, "all" = all externals, id = specific).
    # ESSENTIAL: Excludes slots where a Service already exists for that date+time+location (prevents duplicates).
    def available_time_slots_for_next_30_days
      time_slots = ClinicManagement::TimeSlot.for_location(current_service_location_id)
      slots_by_weekday = time_slots.group_by(&:weekday)

      # Build set of occupied (date, start_time_str, service_location_id) to exclude
      existing_services = Service.for_location(current_service_location_id)
        .where(date: Date.current..Date.current + 29.days)
        .pluck(:date, :start_time, :service_location_id)
      format_time_for_key = ->(t) { t.respond_to?(:strftime) ? t.strftime("%H:%M") : t.to_s[0, 5] }
      existing_key = ->(date, start_time, loc_id) { [date, format_time_for_key.call(start_time), loc_id] }
      occupied_set = existing_services.map { |d, st, loc| existing_key.call(d, st, loc) }.to_set

      (Date.current..Date.current + 29.days).flat_map do |date|
        weekday = date.wday == 6 ? 7 : date.wday + 1
        (slots_by_weekday[weekday] || []).reject do |time_slot|
          occupied_set.include?(existing_key.call(date, time_slot.start_time, time_slot.service_location_id))
        end.map do |time_slot|
          formatted_time = "#{time_slot.start_time.strftime('%H:%M')} - #{time_slot.end_time.strftime('%H:%M')}"
          formatted_time += " (#{time_slot.service_location&.name})" if time_slot.service_location_id.present? && current_service_location_id.to_s == "all"
          {
            date: date,
            time_slot: time_slot,
            formatted_date: "#{I18n.t('date.day_names')[date.wday]}, #{date.strftime('%d/%m/%Y')}",
            formatted_time: formatted_time
          }
        end
      end
    end

    def next_30_days_time_slots(service = nil)
      # Verificar se o serviço existe e se a data já passou
      if service && service.date && service.date < Date.current
        display_info = "#{service.date.strftime('%d/%m/%Y')} - #{I18n.t('date.day_names')[service.date.wday]} - #{service.start_time.strftime('%H:%M')} até #{service.end_time.strftime('%H:%M')}"
        {type: 'text', value: display_info, input: :time_slot_id, name: 'Dias e horários disponíveis', disabled: true}
      else
        # Agrupar slots de tempo por dia da semana (scoped by current service location)
        time_slots = ClinicManagement::TimeSlot.for_location(current_service_location_id).group_by(&:weekday)
    
        # Buscar serviços existentes nos próximos 30 dias (scoped by current location filter), excluindo o serviço atual
        existing_services = Service.for_location(current_service_location_id)
          .where(date: Date.current..Date.current + 29.days)
          .where.not(id: service&.id)
          .pluck(:date, :start_time, :service_location_id)
        format_time_for_key = ->(t) { t.respond_to?(:strftime) ? t.strftime("%H:%M") : t.to_s[0, 5] }
        existing_key = ->(date, start_time, loc_id) { [date, format_time_for_key.call(start_time), loc_id] }
        existing_set = existing_services.map { |d, st, loc| existing_key.call(d, st, loc) }.to_set
    
        options = (Date.current..Date.current + 29.days).flat_map do |date|
          weekday = date.wday == 6 ? 7 : date.wday + 1
          weekday_slots = time_slots[weekday] || []
    
          weekday_slots.reject do |slot|
            # Verificar se o slot específico já está ocupado por um serviço existente (same date, time, location)
            existing_set.include?(existing_key.call(date, slot.start_time, slot.service_location_id))
          end.map do |slot|
            display_info = "#{date.strftime('%d/%m/%Y')} - #{I18n.t('date.day_names')[date.wday]} - #{slot.start_time.strftime('%H:%M')} até #{slot.end_time.strftime('%H:%M')}"
            value = {time_slot_id: slot.id, date: date}.to_json
            [display_info, value]
          end
        end.compact
    
        # Verificar se a opção específica do dia atual do serviço já existe nas opções regulares
        service_slot_exists = false
        if service && service.date && service.date >= Date.current
          slot = ClinicManagement::TimeSlot.find_by(weekday: service.date.wday == 6 ? 7 : service.date.wday + 1, start_time: service.start_time, service_location_id: service.service_location_id)
          if slot
            service_slot_value = {time_slot_id: slot.id, date: service.date}.to_json
            service_slot_exists = options.any? { |_, value| value == service_slot_value }
          end
        end
    
        # Adicionar a opção específica para o dia atual do serviço, se existir e não estiver presente nas opções regulares
        if service && service.date && service.date >= Date.current && !service_slot_exists
          slot = ClinicManagement::TimeSlot.find_by(weekday: service.date.wday == 6 ? 7 : service.date.wday + 1, start_time: service.start_time, service_location_id: service.service_location_id)
          if slot
            display_info = "#{service.date.strftime('%d/%m/%Y')} - #{I18n.t('date.day_names')[service.date.wday]} - #{service.start_time.strftime('%H:%M')} até #{service.end_time.strftime('%H:%M')}"
            value = {time_slot_id: slot.id, date: service.date}.to_json
            options.unshift([display_info, value])
          end
        end
    
        # Verificar se o serviço existe e encontrar o valor selecionado anteriormente
        selected_value = if service && service.date && service.start_time
          slot = ClinicManagement::TimeSlot.find_by(weekday: service.date.wday == 6 ? 7 : service.date.wday + 1, start_time: service.start_time, service_location_id: service.service_location_id)
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
