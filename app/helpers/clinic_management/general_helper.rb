module ClinicManagement
    module GeneralHelper

      def is_operator_above?
        if current_user.present?
            if ["operator", "manager", "owner"].include? current_user.memberships.first.role
                return true
            else
                return false
            end
        else
            return false
        end
    end

    def is_basic_above?
        if current_user.present?
            if ["basic", "operator", "manager", "owner"].include? current_user.memberships.first.role
                return true
            else
                return false
            end
        else
            return false
        end
    end

    def is_manager_above?
        if current_user.present?
            if ["manager", "owner"].include? current_user.memberships.first.role
                return true
            else
                return false
            end
        else
            return false
        end
    end

    def is_owner?
        if current_user.present?
            if current_user.memberships.first.role == "owner"
                return true
            else
                return false
            end
        else
            return false
        end
    end

        def whatsapp_link(phone, message = "")
          decoded_message = CGI.unescape(message)
          "whatsapp://send?phone=55#{phone}&text=#{decoded_message}"
        end

        def add_phone_mask(phone)
          phone&.gsub(/[^0-9]/, '')&.gsub(/(\d{2})(\d{5})(\d{4})/, '\1 \2-\3')
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

        def allowed_to_access_leads?(current_user)
          return false if doctor?(current_user)
          if referral?(current_user)
            referral = user_referral
            referral&.can_access_leads
          else
            true
          end
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
            when 1, "Sunday"
              "Domingo"
            when 2, "Monday"
              "Segunda-feira"
            when 3, "Tuesday"
              "Terça-feira"
            when 4, "Wednesday"
              "Quarta-feira"
            when 5, "Thursday"
              "Quinta-feira"
            when 6, "Friday"
              "Sexta-feira"
            when 7, "Saturday"
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
          

        def clinical_assistant?(user)
          current_membership.role == "clinical_assistant"
        end

    end
  end
  