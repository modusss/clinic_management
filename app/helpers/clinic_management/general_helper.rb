module ClinicManagement
    module GeneralHelper

      def mobile_device?
        request.user_agent =~ /Mobile|webOS|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
      end


      def color_to_hex(color_name, shade)
        color_map = {
          'red' => {
            '100' => '#fee2e2',
            '500' => '#ef4444',
            '700' => '#b91c1c'
          },
          'blue' => {
            '100' => '#dbeafe',
            '500' => '#3b82f6',
            '700' => '#1d4ed8'
          },
          'green' => {
            '100' => '#dcfce7',
            '500' => '#22c55e',
            '700' => '#15803d'
          },
          'yellow' => {
            '100' => '#fef9c3',
            '500' => '#eab308',
            '700' => '#a16207'
          },
          'purple' => {
            '100' => '#f3e8ff',
            '500' => '#a855f7',
            '700' => '#7e22ce'
          },
          'indigo' => {
            '100' => '#e0e7ff',
            '500' => '#6366f1',
            '700' => '#4338ca'
          },
          'pink' => {
            '100' => '#fce7f3',
            '500' => '#ec4899',
            '700' => '#be185d'
          }
        }
      
        color_map.dig(color_name, shade) || '#000000'
      end

    def send_api_zap_pdf(pdf_url, caption, phone, delay, instance_name = nil)
      instance_name = instance_name || Account.first.evolution_instance_name

      if delay.present?
          custom_delay
      end
      base_url = Account.last.evolution_base_url
      api_key = Account.last.evolution_api_key
      # Codifica o nome da instância para ser usado na URL
      encoded_instance_name = url_encode(instance_name)
      # Preparando o cabeçalho com a chave da API
      headers = {
      "Content-Type" => "application/json",
      "apikey" => api_key
      }
      # v2: Estrutura simplificada - campos diretos no body
      body = {
      number: "55" + phone,
      mediatype: "document",  # v2: campo direto
      mimetype: "application/pdf",
      caption: caption,
      media: pdf_url,
      delay: 1200,
      linkPreview: false
      }.to_json
      # Montando o endpoint com o nome da instância codificado corretamente
      endpoint = "#{base_url}/message/sendMedia/#{encoded_instance_name}"
      # Fazendo a solicitação POST
      response = HTTParty.post(
      endpoint,
      body: body,
      headers: headers
      )
      # Retorna a resposta da API
      response
    end


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

      def available_services(exception_service)
        exception_service_id = exception_service.id # Get the ID of the exception_service object
        today = Time.zone.today # Use Time.zone.today instead of Date.current
        ClinicManagement::Service.where(canceled: [nil, false]).where("date >= ? AND id != ?", today, exception_service_id)
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
          formatted_message = message.gsub("\n", "%0A")
          "whatsapp://send?phone=55#{phone}&text=#{formatted_message}"
        end

        def add_phone_mask(phone)
          phone&.gsub(/[^0-9]/, '')&.gsub(/(\d{2})(\d{5})(\d{4})/, '(\1) \2-\3')
        end

        # Returns an HTML link with the masked phone number that opens WhatsApp chat when clicked,
        # and a phone icon with "Ligar" text next to it that allows direct calling from mobile devices,
        # making it explicit that clicking will dial the number.
        def masked_whatsapp_link(phone, message = "")
          masked_phone = add_phone_mask(phone)
          whatsapp = whatsapp_link(phone, message)
          tel_link = "tel:+55#{phone&.gsub(/[^0-9]/, '')}"

          # WhatsApp icon, masked phone, and explicit call link with icon and "Ligar" text
          "<a href=\"#{whatsapp}\" target=\"_blank\" rel=\"noopener\" style=\"text-decoration:none;font-weight:500;\" class=\"nowrap text-blue-500 hover:text-blue-700\">
            <i class=\"fab fa-whatsapp\" style=\"margin-right:6px;\"></i>#{masked_phone}
          </a>
          <a href=\"#{tel_link}\" style=\"margin-left:12px;color:#4B5563;text-decoration:none;display:inline-flex;align-items:center;\" title=\"Ligar para #{masked_phone}\">
            <i class=\"fas fa-phone-alt\" style=\"margin-right:4px;\"></i>
            <span style=\"font-size:15px;\">Ligar</span>
          </a>".html_safe
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

        # Verifica se o usuário pode acessar TODOS os leads ou apenas os que ele registrou
        # Doctors não podem acessar
        # Referrals sempre podem acessar, mas com acesso filtrado baseado em can_access_leads
        # Outros usuários têm acesso completo
        def allowed_to_access_all_leads?(current_user)
          return false if doctor?(current_user)
          if referral?(current_user)
            referral = user_referral
            referral&.can_access_leads
          else
            true
          end
        end
        
        # Verifica se pode acessar a página de leads (mesmo que com filtro)
        def allowed_to_access_leads?(current_user)
          return false if doctor?(current_user)
          true  # Referrals e outros usuários podem acessar (com filtros aplicados)
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
          return "" unless service.present?
          
          date_info = "#{show_week_day(service.weekday)}, #{service.date.strftime('%d/%m/%Y')}"
          time_info = "#{service.start_time.strftime('%H:%M')}h às #{service.end_time.strftime('%H:%M')}h"
          
          # Create a card with better organized elements
          html = "<div class=\"appointment-card\">
            <div class=\"appointment-date\">
              <i class=\"far fa-calendar-alt\"></i>
              <span>#{date_info}</span>
            </div>
            <div class=\"appointment-time\">
              <i class=\"far fa-clock\"></i>
              <span>#{time_info}</span>
            </div>
          </div>"
          
          # Add inline styles for the card
          style = "<style>
            .appointment-card {
              background-color: #f8f9ff;
              border-radius: 8px;
              padding: 12px 16px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.05);
              max-width: 300px;
              margin: 10px 0;
              border-left: 4px solid #4285f4;
            }
            .appointment-date, .appointment-time {
              display: flex;
              align-items: center;
              color: #4285f4;
              margin: 6px 0;
            }
            .appointment-date i, .appointment-time i {
              margin-right: 10px;
              font-size: 18px;
            }
            .appointment-date span, .appointment-time span {
              font-size: 16px;
              font-weight: 500;
            }
          </style>"
          
          (style + html).html_safe
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

        # Evolution API message sending helpers
        def send_evolution_message_with_media(phone, message_text, media_details, instance_name = nil)
          # Use the main helper functions from GeneralHelper
          helper = Object.new.extend(::GeneralHelper)
          Rails.logger.info "🔧 Helper method called with phone: #{phone}, instance: #{instance_name}, media: #{media_details.present?}"
          
          if media_details.present? && media_details[:url].present?
            Rails.logger.info "📎 Sending media message - type: #{media_details[:type]}"
            case media_details[:type]
            when 'image'
              caption = media_details[:caption].present? ? media_details[:caption] : message_text
              helper.send_api_zap_image(media_details[:url], caption, phone, false, instance_name)
            when 'audio'
              helper.send_api_zap_audio(media_details[:url], phone, false, instance_name)
            when 'video'
              caption = [media_details[:caption], message_text].reject(&:blank?).join("\n\n")
              helper.send_api_zap_video(media_details[:url], caption, phone, false, instance_name)
            when 'document'
              caption = [media_details[:caption], message_text].reject(&:blank?).join("\n\n")
              helper.send_api_zap_pdf(media_details[:url], caption, phone, false, instance_name)
            else
              # Fallback to document for unknown types
              caption = [media_details[:caption], message_text].reject(&:blank?).join("\n\n")
              helper.send_api_zap_pdf(media_details[:url], caption, phone, false, instance_name)
            end
          else
            # Send text message only
            Rails.logger.info "💬 Sending text message"
            helper.send_api_zap_message(message_text, phone, false, instance_name)
          end
        end

        def format_evolution_response(response)
          # Use the main helper function for response formatting
          helper = Object.new.extend(::GeneralHelper)
          helper.response_feedback_api_zap(response)
        end

        # ========================================
        # Métodos de Envio Evolution API
        # ========================================

        def custom_delay
          sleep(rand(1..3))
        end

        def send_api_zap_message(message, phone, delay, instance_name = nil)
          return { "status" => 400, "error" => "Invalid phone or message" } if phone.blank? || message.blank? || phone.nil?       
          
          instance_name = instance_name || Account.first.evolution_instance_name
          
          if (delay == true) || (delay == "true")
            custom_delay
          end
          
          base_url = Account.last.evolution_base_url
          api_key = Account.last.evolution_api_key
          encoded_instance_name = ERB::Util.url_encode(instance_name)
          
          headers = {
            "Content-Type" => "application/json",
            "apikey" => api_key
          }
          
          body = {
            number: "55" + phone.to_s,
            textMessage: {
              text: message
            },
            options: {
              delay: 10,
              presence: "composing",
              linkPreview: false
            }
          }.to_json
          
          endpoint = "#{base_url}/message/sendText/#{encoded_instance_name}"
          
          response = HTTParty.post(
            endpoint,
            body: body,
            headers: headers
          )
          
          response
        end

        def send_api_zap_image(media_url, caption, phone, delay, instance_name = nil)
          instance_name = instance_name || Account.first.evolution_instance_name

          if (delay == true) || (delay == "true")
            custom_delay
          end
          
          base_url = Account.last.evolution_base_url
          api_key = Account.last.evolution_api_key
          encoded_instance_name = ERB::Util.url_encode(instance_name)
          
          headers = {
            "Content-Type" => "application/json",
            "apikey" => api_key
          }
          
          body = {
            number: "55" + phone,
            options: {
              delay: 10,
              presence: "composing",
              linkPreview: false
            },
            mediaMessage: {
              mediatype: "image",
              caption: caption,
              media: media_url
            }
          }.to_json
          
          endpoint = "#{base_url}/message/sendMedia/#{encoded_instance_name}"
          
          response = HTTParty.post(
            endpoint,
            body: body,
            headers: headers
          )
          
          response
        end

        def send_api_zap_video(video_url, caption, phone, delay, instance_name = nil)
          instance_name = instance_name || Account.first.evolution_instance_name

          if (delay == true) || (delay == "true")
            custom_delay
          end
          
          base_url = Account.last.evolution_base_url
          api_key = Account.last.evolution_api_key
          encoded_instance_name = ERB::Util.url_encode(instance_name)
          
          headers = {
            "Content-Type" => "application/json",
            "apikey" => api_key
          }
          
          body = {
            number: "55" + phone,
            options: {
              delay: 10,
              presence: "composing"
            },
            mediaMessage: {
              mediatype: "video",
              caption: caption,
              media: video_url
            }
          }.to_json
          
          endpoint = "#{base_url}/message/sendMedia/#{encoded_instance_name}"
          
          response = HTTParty.post(
            endpoint,
            body: body,
            headers: headers
          )
          
          response
        end

        def send_api_zap_audio(audio_url, phone, delay, instance_name = nil)
          instance_name = instance_name || Account.first.evolution_instance_name

          if (delay == true) || (delay == "true")
            custom_delay
          end
          
          base_url = Account.last.evolution_base_url
          api_key = Account.last.evolution_api_key
          encoded_instance_name = ERB::Util.url_encode(instance_name)
          
          headers = {
            "Content-Type" => "application/json",
            "apikey" => api_key
          }
          
          body = {
            number: "55" + phone,
            options: {
              delay: 10,
              presence: "composing",
              linkPreview: false
            },
            mediaMessage: {
              mediatype: "audio",
              media: audio_url
            }
          }.to_json
          
          endpoint = "#{base_url}/message/sendMedia/#{encoded_instance_name}"
          
          response = HTTParty.post(
            endpoint,
            body: body,
            headers: headers
          )
          
          response
        end

        def send_api_zap_pdf(pdf_url, caption, phone, delay, instance_name = nil)
          instance_name = instance_name || Account.first.evolution_instance_name

          if (delay == true) || (delay == "true")
            custom_delay
          end
          
          base_url = Account.last.evolution_base_url
          api_key = Account.last.evolution_api_key
          encoded_instance_name = ERB::Util.url_encode(instance_name)
          
          headers = {
            "Content-Type" => "application/json",
            "apikey" => api_key
          }
          
          body = {
            number: "55" + phone,
            options: {
              delay: 10,
              presence: "composing"
            },
            mediaMessage: {
              mediatype: "document",
              caption: caption,
              media: pdf_url,
              fileName: "documento.pdf"
            }
          }.to_json
          
          endpoint = "#{base_url}/message/sendMedia/#{encoded_instance_name}"
          
          response = HTTParty.post(
            endpoint,
            body: body,
            headers: headers
          )
          
          response
        end

    end

    # Helper method for performance report conversion badges
    def conversion_class(rate)
      if rate >= 40
        'excellent'
      elsif rate >= 30
        'good'
      elsif rate >= 20
        'average'
      else
        'low'
      end
    end
end