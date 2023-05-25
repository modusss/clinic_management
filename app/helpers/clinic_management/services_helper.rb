module ClinicManagement
  module ServicesHelper
    def description_service(service)
      "#{service.date.strftime("%d/%m/%Y")} - #{show_week_day(service.weekday)} (#{service.start_time.strftime("%H:%M")} - #{service.end_time.strftime("%H:%M")})"
    end

    def display_service_name(service)
      start_time = service.start_time.strftime("%H:%Mh")
      end_time = service.end_time.strftime("%H:%Mh")
      "#{show_week_day(service.weekday)}, #{service.date.strftime("%d/%m/%Y")} - #{start_time} às #{end_time}"
    end
  end
end
