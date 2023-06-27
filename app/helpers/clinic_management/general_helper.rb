module ClinicManagement
    module GeneralHelper

        def whatsapp_link(phone, message = "")
          "https://api.whatsapp.com/send/?phone=+55#{phone}&text=#{message}"
        end

        def referral?(user)
          current_membership.role == "referral"
        end

        def doctor?(user)
          current_membership.role == "doctor"
        end

        def user_referral
          code = current_membership.code
          Referral.find_by(code: code)
        end
        
        def current_membership
          current_user&.memberships&.last
        end

        def local_referral
          referral = Referral.where(name: "Local").first
          unless referral.present?
              Referral.create(name: "Local")
          end
          return referral
        end

        def format_day_of_week(date)
            I18n.l(date, format: "%A")
        end

        def format_month(date)
            I18n.l(date, format: "%B")
        end
          

        def status_class(appointment)
            case appointment.status
            when "agendado"
                "text-yellow-600"
            when "remarcado"
                "text-purple-600"
            when "cancelado"
                "text-red-600"
            else
                ""
            end
        end

        def attendance_class(appointment)
            appointment.attendance ? "text-green-600" : "text-red-600"
        end

        def invite_day(appointment)
            service = appointment&.service
            if service.present?
              show_week_day(service.weekday) + " " + service.date.strftime("%d/%m") + ", " + service.start_time.strftime("%H:%M") + "h às " + service.end_time.strftime("%H:%M") + "h"
            else
              ""
            end
        end


        def show_week_day(weekday)
            case weekday
            when 1
              "Domingo"
            when 2
              "Segunda-feira"
            when 3
              "Terça-feira"
            when 4
              "Quarta-feira"
            when 5
              "Quinta-feira"
            when 6
              "Sexta-feira"
            when 7
              "Sábado"
            end
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
  