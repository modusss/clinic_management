module ClinicManagement
  module PrescriptionsHelper

    def translate_type(type)
      case type
      when 'sphere'
        'Esférico'
      when 'cylinder'
        'Cilindro'
      when 'axis'
        'Eixo'
      when 'add'
        'Adição'
      else
        type
      end
    end

    def translate_side(side)
      case side
      when 'right'
        'Direito'
      when 'left'
        'Esquerdo'
      else
        side
      end
    end

    def collection_for_sphere
      (-25..25).step(0.25).map { |x| x.positive? ? "+#{x.round(2)}" : x.round(2).to_s }
    end
    
    def collection_for_cylinder
      (-10..0).step(0.25).map { |x| x.round(2) }
    end

    def collection_for_axis
      (0..180).to_a
    end

    def collection_for_add
      (0..3.5).step(0.25).map { |x| x.positive? ? "+#{x.round(2)}" : x.round(2).to_s }

    end


    # Método auxiliar para centralizar lógica de ícones/cores do attendance
    def attendance_info(appointment)
      if appointment.attendance
        [
          "COMPARECEU",
          "bg-green-100 text-green-800 px-2 py-1 rounded-full text-sm font-medium",
          heroicon_check_circle
        ]
      elsif appointment.service.date < Date.current
        [
          "FALTOU",
          "bg-red-100 text-red-800 px-2 py-1 rounded-full text-sm font-medium",
          heroicon_x_circle
        ]
      else
        [
          "AGUARDANDO",
          "bg-yellow-100 text-yellow-800 px-2 py-1 rounded-full text-sm font-medium",
          heroicon_clock
        ]
      end
    end

      def format_status_and_attendance(appointment)
        # Pegamos o status e colocamos em UPPERCASE para exibir
        status_text = appointment.status&.upcase
        attendance_text, attendance_classes, attendance_icon = attendance_info(appointment)

        content_tag(:div, class: "flex flex-col gap-1") do
          safe_join([
            # Status principal (Remarcado, Cancelado ou outro)
            content_tag(:div, class: "font-medium") do
              case status_text&.downcase
              when "remarcado"
                # Exemplo de ícone de "flecha circular" para remarcado
                %(
                  <span class="inline-flex items-center gap-1 bg-blue-100 text-blue-800 px-2 py-1 rounded-full text-sm">
                    #{heroicon_refresh} REMARCADO
                  </span>
                ).html_safe
              when "cancelado"
                # Exemplo de ícone de "ban"
                %(
                  <span class="inline-flex items-center gap-1 bg-gray-100 text-gray-800 px-2 py-1 rounded-full text-sm">
                    #{heroicon_ban} CANCELADO
                  </span>
                ).html_safe
              else
                # Se não é remarcado ou cancelado, exibimos só o texto
                # (aqui você pode personalizar ainda mais se quiser)
                status_text
              end
            end,
            # Status de atendimento (Compareceu, Faltou, Aguardando)
            content_tag(:div) do
              %(
                <span class="inline-flex items-center gap-1 #{attendance_classes}">
                  #{attendance_icon} #{attendance_text}
                </span>
              ).html_safe
            end
          ])
        end
      end

      # Método auxiliar para centralizar lógica de ícones/cores do attendance
      def attendance_info(appointment)
        if appointment.attendance
          [
          "COMPARECEU",
          "bg-green-100 text-green-800 px-2 py-1 rounded-full text-sm font-medium",
          heroicon_check_circle
          ]
        elsif appointment.service.date < Date.current
          [
          "FALTOU",
          "bg-red-100 text-red-800 px-2 py-1 rounded-full text-sm font-medium",
          heroicon_x_circle
          ]
        else
          [
          "AGUARDANDO",
          "bg-yellow-100 text-yellow-800 px-2 py-1 rounded-full text-sm font-medium",
          heroicon_clock
          ]
        end
      end


  # Exemplos de métodos que retornam SVGs para ícones Heroicons.
  # Substitua pelo que você preferir ou remova se já estiver usando algo como o HeroiconHelper/Rails icons, Font Awesome, etc.

  def heroicon_check_circle
    content_tag(:i, "", class: "fas fa-check-circle")
  end

  def heroicon_x_circle
    content_tag(:i, "", class: "fas fa-times-circle")
  end
  

  def heroicon_clock
    content_tag(:i, "", class: "fas fa-clock")
  end

  def heroicon_refresh
    content_tag(:i, "", class: "fas fa-sync")
  end

  def heroicon_ban
    content_tag(:i, "", class: "fas fa-ban")
  end

  end
end
