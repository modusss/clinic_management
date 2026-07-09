module ClinicManagement
  module ApplicationHelper
    include ReferralDisplayLabelsHelper

    CLINIC_PAGE_TITLE_OVERRIDES = {
      "clinic_management/appointments#index" => "agendamentos",
      "clinic_management/appointments#show" => "agendamento",
      "clinic_management/invitations#new" => "novo paciente",
      "clinic_management/lead_messages#index" => "mensagens customizadas",
      "clinic_management/leads#index" => "pacientes",
      "clinic_management/prescriptions#index_today" => "lista de hoje",
      "clinic_management/prescriptions#index_next" => "próximo atendimento",
      "clinic_management/prescriptions#index_before" => "atendimento anterior",
      "clinic_management/referral_indicators#index" => "captadores",
      "clinic_management/regions#index" => "regiões de captação",
      "clinic_management/service_locations#index" => "locais de atendimento",
      "clinic_management/service_types#index" => "tipos de serviço",
      "clinic_management/services#index" => "atendimentos",
      "clinic_management/services#show" => "atendimento",
      "clinic_management/time_slots#index" => "horários de marcações"
    }.freeze

    CLINIC_CONTROLLER_BROWSER_LABELS = {
      "appointments" => ["agendamentos", "agendamento"],
      "invitations" => ["convites", "convite"],
      "lead_messages" => ["mensagens customizadas", "mensagem customizada"],
      "leads" => ["pacientes", "paciente"],
      "prescriptions" => ["atendimentos", "atendimento"],
      "referral_indicators" => ["captadores", "captador"],
      "regions" => ["regiões de captação", "região de captação"],
      "service_locations" => ["locais de atendimento", "local de atendimento"],
      "service_types" => ["tipos de serviço", "tipo de serviço"],
      "services" => ["atendimentos", "atendimento"],
      "time_slots" => ["horários de marcações", "horário de marcação"]
    }.freeze

    CLINIC_BROWSER_TITLE_TERM_TRANSLATIONS = {
      "appointments" => "agendamentos",
      "booking" => "agendamento",
      "bookings" => "agendamentos",
      "edit" => "editar",
      "index" => "lista",
      "invitations" => "convites",
      "leads" => "pacientes",
      "new" => "novo",
      "prescriptions" => "atendimentos",
      "referral" => "captação",
      "regions" => "regiões",
      "self" => "auto",
      "service" => "atendimento",
      "services" => "atendimentos",
      "show" => "detalhes",
      "slots" => "horários",
      "time" => "horários"
    }.freeze

    # Builds the clinic browser tab title using the same convention as the main app:
    # environment prefix + clinic product name + current page label.
    #
    # @param default_page_title [String, nil]
    # @return [String]
    def clinic_browser_title(default_page_title: nil)
      page_title = clinic_browser_page_title(default_page_title)
      title = page_title.present? ? "LP atendimento - #{page_title}" : "LP atendimento"

      "#{clinic_browser_environment_title_prefix}#{title}"
    end

    # ESSENTIAL: Display name for Service in dropdowns (navbar "Ir para atendimento...").
    # Format: "Quinta-feira, 05/03/2026 - 08:00h às 12:00h".
    # When "Todos externos" selected: Local as FIRST param so user can distinguish services from different locations.
    def display_service_name(service)
      return "" if service.blank?
      weekday = TimeSlotsHelper::WEEKDAY_NAMES[service.weekday.to_i] || ""
      date_str = service.date&.strftime("%d/%m/%Y") || ""
      times = [service.start_time&.strftime('%H:%M'), service.end_time&.strftime('%H:%M')].compact
      time_str = times.size == 2 ? "#{times[0]}h às #{times[1]}h" : ""
      base = [weekday, date_str].reject(&:blank?).join(", ")
      base += " - #{time_str}" if time_str.present?
      # When showing all externals, put Local FIRST so user can tell which service is which
      if current_service_location_id.to_s == "all" && service.service_location.present?
        base = "Local: #{service.service_location.name}, #{base}"
      end
      base
    end

    # Converte imagem do Active Storage para base64 para uso em PDFs
    def active_storage_image_base64(attachment)
      return nil unless attachment.attached?
      
      begin
        image_data = attachment.download
        content_type = attachment.content_type
        base64_data = Base64.strict_encode64(image_data)
        
        "data:#{content_type};base64,#{base64_data}"
      rescue StandardError => e
        Rails.logger.error "Erro ao converter imagem para base64: #{e.message}"
        nil
      end
    end

    # @param default_page_title [String, nil]
    # @return [String, nil]
    def clinic_browser_page_title(default_page_title)
      explicit_title = translated_clinic_browser_title(clinic_normalized_content_for_browser_title)
      return explicit_title if explicit_title.present?
      return translated_clinic_browser_title(default_page_title) if default_page_title.present?

      translated_clinic_browser_title(CLINIC_PAGE_TITLE_OVERRIDES[clinic_page_title_key] || inferred_clinic_browser_page_title)
    end

    # @return [String]
    def clinic_browser_environment_title_prefix
      if Rails.env.development?
        "DEV/ "
      elsif Rails.env.production?
        ""
      else
        "STAG/ "
      end
    end

    # @return [String]
    def clinic_page_title_key
      "#{controller_path}##{action_name}"
    end

    # @return [String, nil]
    def clinic_normalized_content_for_browser_title
      return nil unless content_for?(:title)

      content_for(:title).to_s
        .squish
        .sub(/\A(?:DEV|STAG)\s*[-\/]\s*/i, "")
        .sub(/\s*(?:\||-|—)\s*LP atendimento\z/i, "")
        .presence
    end

    # Keeps clinic browser titles in pt-BR even when a fallback sees internal names.
    #
    # @param raw_title [String, nil]
    # @return [String, nil]
    def translated_clinic_browser_title(raw_title, fallback: nil, strict: false)
      title = raw_title.to_s.squish
      return nil if title.blank?

      source = title.tr("_", " ").squish
      translated = source.split(/\b/).map do |token|
        CLINIC_BROWSER_TITLE_TERM_TRANSLATIONS.fetch(token.downcase, token)
      end.join.squish

      if translated == source
        return fallback if fallback.present? || strict
      end

      translated
    end

    # @return [String]
    def inferred_clinic_browser_page_title
      plural_label, singular_label = CLINIC_CONTROLLER_BROWSER_LABELS.fetch(controller_name) do
        label = translated_clinic_browser_title(controller_name, strict: true)
        [label, label&.singularize]
      end
      return nil if plural_label.blank? && singular_label.blank?

      case action_name
      when "index"
        plural_label
      when "show"
        singular_label
      when "new"
        return nil if singular_label.blank?

        "novo #{singular_label}"
      when "edit"
        return nil if singular_label.blank?

        "editar #{singular_label}"
      else
        action_label = translated_clinic_browser_title(action_name, strict: true)
        return plural_label if action_label.blank?
        return plural_label if action_label == plural_label

        "#{action_label} - #{plural_label}"
      end
    end

  #
  # TABELA DE DADOS COM ESTILOS REFINADOS (data_table)
  # - rows (Array<Hash>): linhas de dados, onde cada linha é um Array de hashes 
  #   com chaves como :header, :content, :class, etc.
  # - fix_to (Integer): quantas colunas devem ficar fixas à esquerda
  #
  def data_table(rows, fix_to = 0)
    content_tag :div, 
                class: "table-container shadow-md rounded-lg", 
                style: "max-height: 70vh",
                data: { 
                  controller: "table",
                  table_fix_columns_value: fix_to 
                } do
      table_wrapper("scrollable", rows, "min-w-full table-auto border-collapse", fix_to)
    end
  end

  #
  # ENVOLVE A TABELA, VERIFICANDO SE HÁ DADOS
  #
  def table_wrapper(id, rows, inner_classes, fix_to)
    # ESSENTIAL: rows may be [nil, ...] if upstream map used `next` without compact — rows.first would be nil and break .map.
    # Also reject non-row values (e.g. search_appointment used to pass "") so only Arrays of cell-hashes are rendered.
    rows = Array.wrap(rows).compact.select { |r| r.is_a?(Array) && r.first.is_a?(Hash) }
    return content_tag(:p, 'Não houve resultados.', class: 'text-gray-500 italic') if rows.empty?

    content_tag(:table, class: inner_classes, id: id) do
      # Cabeçalho
      table_header(rows.first.map { |cell| cell[:header] }, fix_to) +
      # Corpo
      table_body(rows, fix_to)
    end
  end

  #
  # MONTA O CABEÇALHO DA TABELA
  #
  def table_header(headers, fix_to)
    content_tag(:thead, class: "bg-white border-b border-gray-200 sticky top-0") do
      content_tag(:tr) do
        headers_html = headers.map.with_index do |header, index|
          # Classes base do TH
          header_class = "px-6 py-3 text-[16px] font-medium text-gray-700 uppercase tracking-wider text-center bg-white border-b border-gray-200"
          # Se for para fixar a coluna
          if index < fix_to
            header_class += " sticky-column sticky left-0 z-20"
          end
          
          content_tag(:th, header, class: header_class)
        end.join.html_safe
        
        # Adicionar cabeçalho "Ações" se estiver na view de ausentes
        if controller_name == 'leads' && action_name == 'absent'
          action_header = content_tag(:th, "Ações", 
            class: "px-6 py-3 text-[16px] font-medium text-gray-700 uppercase tracking-wider text-center bg-white border-b border-gray-200")
          headers_html + action_header
        else
          headers_html
        end
      end
    end
  end

#
# MONTA O CORPO DA TABELA
#
def table_body(rows, fix_to)
  content_tag(:tbody, class: "divide-y divide-gray-200") do
    rows.map.with_index do |row, row_index|
      next if row.nil?
      
      row_class = "border-b hover:bg-gray-50 odd:bg-white even:bg-gray-50"
      row_class += " #{row.first[:row_class]}" if row.first && row.first[:row_class].present?
      
      # Adicionar ID único para cada linha baseado no lead
      row_id = row.first[:row_id] || "table-row-#{row_index}"

      tr_options = { class: row_class, id: row_id }
      # ESSENTIAL: Enables doctor_attendance_filter Stimulus on prescriptions/index_today rows.
      if row.first[:attendance_status].present?
        tr_options[:data] = {
          doctor_attendance_filter_target: "item",
          attendance: row.first[:attendance_status]
        }
      end

      content_tag(:tr, **tr_options) do
        cells_html = row.map.with_index do |cell, index|
          # Verifica o número de palavras no conteúdo
          content = cell[:content].to_s
          word_count = content.split.size
          
          # Classe base para TD
          cell_class = "px-6 py-4 text-gray-900 text-center text-[16px]"
          
          # Adiciona estilo específico se ultrapassar 6 palavras
          if word_count > 6
            cell_class += " !min-w-[100px] whitespace-normal"
          else
            cell_class += " whitespace-nowrap"
          end
          
          # Se a coluna é fixa
          if index < fix_to
            cell_class += " sticky-column sticky left-0 z-10"
          end
          
          # Adiciona classes personalizadas caso existam
          cell_class += " #{cell[:class]}" if cell[:class].present?

          # Cria a célula final
          content_tag(:td, cell[:content], id: cell[:id], class: cell_class)
        end.join.html_safe
        
        # Adicionar botões de ação como última coluna se estiver na view de ausentes
        if controller_name == 'leads' && action_name == 'absent'
          action_buttons_cell = content_tag(:td, class: "px-6 py-4 text-center") do
            lead = controller.instance_variable_get(:@leads)[row_index]
            
            if params[:hidden_status] == "visible" || params[:hidden_status].blank?
              # Três botões horizontalmente
              content_tag(:div, class: "flex flex-wrap gap-2 justify-center items-center") do
                btn1 = button_to clinic_management.hide_from_absent_lead_path(lead), 
                  method: :patch,
                  remote: true,
                  data: { 
                    turbo_method: :patch,
                    turbo_stream: true,
                    confirm: "Tem certeza que deseja ocultar este lead da listagem?"
                  },
                  class: "bg-red-500 hover:bg-red-600 active:bg-red-700 text-white text-xs px-2 py-1 rounded shadow-sm flex items-center gap-1 whitespace-nowrap",
                  title: "Ocultar da lista" do
                  content_tag(:i, "", class: "fas fa-calendar-plus") + " Contato futuro"
                end
                
                btn2 = button_to clinic_management.mark_no_interest_lead_path(lead), 
                  method: :patch,
                  remote: true,
                  data: { 
                    turbo_method: :patch,
                    turbo_stream: true,
                    confirm: "Marcar este lead como 'Sem interesse'?"
                  },
                  class: "bg-gray-500 hover:bg-gray-600 active:bg-gray-700 text-white text-xs px-2 py-1 rounded shadow-sm flex items-center gap-1 whitespace-nowrap",
                  title: "Sem interesse" do
                  content_tag(:i, "", class: "fas fa-times") + " Sem Interesse"
                end
                
                btn3 = button_to clinic_management.mark_wrong_phone_lead_path(lead), 
                  method: :patch,
                  remote: true,
                  data: { 
                    turbo_method: :patch,
                    turbo_stream: true,
                    confirm: "Marcar este lead como 'Telefone errado'?"
                  },
                  class: "bg-orange-500 hover:bg-orange-600 active:bg-orange-700 text-white text-xs px-2 py-1 rounded shadow-sm flex items-center gap-1 whitespace-nowrap",
                  title: "Telefone errado" do
                  content_tag(:i, "", class: "fas fa-phone-slash") + " Telefone errado"
                end
                
                btn1 + btn2 + btn3
              end
            else
              # Botão para restaurar
              button_to clinic_management.restore_lead_lead_path(lead), 
                method: :patch,
                remote: true,
                data: { 
                  turbo_method: :patch,
                  turbo_stream: true,
                  confirm: "Tem certeza que deseja restaurar este lead na listagem principal?"
                },
                class: "bg-green-500 hover:bg-green-600 active:bg-green-700 text-white text-xs px-3 py-1 rounded shadow-sm flex items-center gap-1 mx-auto",
                title: "Restaurar na lista principal" do
                content_tag(:i, "", class: "fas fa-undo") + " Restaurar"
              end
            end
          end
          cells_html + action_buttons_cell
        else
          cells_html
        end
      end
    end.compact.join.html_safe
  end
end

    
  end
end
