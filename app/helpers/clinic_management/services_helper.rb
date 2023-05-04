module ClinicManagement
  module ServicesHelper
    def description_service(service)
      "#{service.date.strftime("%d/%m/%Y")} - #{show_week_day(service.weekday)} (#{service.start_time.strftime("%H:%M")} - #{service.end_time.strftime("%H:%M")})"
    end
  end
end
