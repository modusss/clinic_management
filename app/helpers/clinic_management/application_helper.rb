module ClinicManagement
  module ApplicationHelper


    def breadcrumb(*crumbs)
      content_for :breadcrumb do
        render "clinic_management/shared/breadcrumb" do
          crumbs.each_with_index.map do |crumb, index|
            is_last = index == crumbs.length - 1
  
            content_tag(:li, class: "flex items-center") do
              concat(link_to(crumb[:title], crumb[:path], class: "#{is_last ? 'text-gray-600' : 'text-blue-600 hover:text-blue-800'}"))
              unless is_last
                concat(content_tag(:svg, class: "flex-shrink-0 h-5 w-5 text-gray-500 mx-4", xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 20 20", fill: "currentColor", aria_hidden: "true") do
                  content_tag(:path, "", d: "M5.555 17.776l8-16 .894.448-8 16-.894-.448z")
                end)
              end
            end
          end.join.html_safe
        end
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
        headers.map.with_index do |header, index|
          # Classes base do TH
          header_class = "px-6 py-3 text-[16px] font-medium text-gray-700 uppercase tracking-wider text-center bg-white border-b border-gray-200"
          # Se for para fixar a coluna
          if index < fix_to
            header_class += " sticky-column sticky left-0 z-20"
          end
          
          content_tag(:th, header, class: header_class)
        end.join.html_safe
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
      
      content_tag(:tr, class: row_class, id: row_id) do
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
        
        # Adicionar botão de ocultar como última coluna se estiver na view de ausentes
        if controller_name == 'leads' && action_name == 'absent'
          hide_button_cell = content_tag(:td, class: "px-6 py-4 text-center") do
            if params[:hidden_status] != "hidden"
              # Botão para ocultar
              button_to clinic_management.hide_from_absent_lead_path(controller.instance_variable_get(:@leads)[row_index]), 
                method: :patch,
                remote: true,
                data: { 
                  turbo_method: :patch,
                  turbo_stream: true,
                  confirm: "Tem certeza que deseja ocultar este lead da listagem? Ele ficará disponível no filtro 'Ocultados da lista'."
                },
                class: "bg-red-500 hover:bg-red-600 text-white text-xs px-2 py-1 rounded",
                title: "Não aparecer mais nesta lista" do
                content_tag(:i, "", class: "fas fa-eye-slash") + " Ocultar"
              end
            else
              # Botão para restaurar
              button_to clinic_management.unhide_from_absent_lead_path(controller.instance_variable_get(:@leads)[row_index]), 
                method: :patch,
                remote: true,
                data: { 
                  turbo_method: :patch,
                  turbo_stream: true,
                  confirm: "Tem certeza que deseja restaurar este lead na listagem?"
                },
                class: "bg-green-500 hover:bg-green-600 text-white text-xs px-2 py-1 rounded",
                title: "Mostrar novamente na lista principal" do
                content_tag(:i, "", class: "fas fa-eye") + " Restaurar"
              end
            end
          end
          cells_html + hide_button_cell
        else
          cells_html
        end
      end
    end.compact.join.html_safe
  end
end

    
  end
end
