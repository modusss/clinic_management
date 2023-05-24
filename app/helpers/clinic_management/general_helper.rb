module ClinicManagement
    module GeneralHelper

        def invite_day(invite)
            service = invite.appointment.service
            helpers.show_week_day(service.weekday) + " " + service.date.strftime("%d/%m") + ", " + service.start_time.strftime("%H:%M") + "h às " + service.end_time.strftime("%H:%M") + "h"
        end

        def render_menu(tabs)
            html = '<div class="mb-6">'
            html += '<ul class="flex border-b">'
          
            tabs.each do |tab|
              html += '<li class="-mb-px mr-2 last:mr-0 flex-auto text-center">'
              html += '<a class="'
              html += 'bg-blue-800 text-white' if controller_name == tab[:controller_name] && action_name == tab[:action_name]
              html += ' text-xs font-bold uppercase px-5 py-3 shadow-lg rounded block leading-normal text-white bg-blue-300"'
              html += " href=\"#{clinic_management.send("#{tab[:url]}_path")}\">"
              html += tab[:url_name]
              html += '</a>'
              html += '</li>'
            end
          
            html += '</ul>'
            html += '</div>'
          
            html.html_safe
        end
          
          

    end
  end
  