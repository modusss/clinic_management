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


    # table with calculation of width


    def data_table(rows, fix_to = 3)
      content_tag(:div, class: "flex overflow-x-scroll", style: "max-height: 70vh; overflow-y: auto;", data: { controller: "table" }) do 
        table_wrapper("scrollable", rows, "min-w-full divide-y divide-gray-200", fix_to)
      end      
    end    
    
    def table_wrapper(id, rows, inner_classes, fix_to)
      if rows.empty?
        return content_tag(:p, 'Não houve resultados.', class: 'text-red-600')
      end
      
      content_tag(:table, class: inner_classes) do
        table_header(rows.first.map { |cell| cell[:header] }, fix_to) + table_body(rows, fix_to)
      end
    end
  
    def table_header(headers, fix_to)
      content_tag(:thead, class: "bg-gray-50") do
        content_tag(:tr) do
          headers.map.with_index do |header, header_index|
            classes = "text-lg px-6 py-3 text-left font-medium text-gray-500 uppercase tracking-wider text-center"
            styles = ''
            if header_index < fix_to
              classes += ' sticky'
            end
            content_tag(:th, header, scope: "col", class: classes, style: styles)
          end.join.html_safe
        end
      end
    end
    
    def table_body(rows, fix_to)
      content_tag(:tbody, class: "bg-white divide-y divide-gray-200") do
        rows.map.with_index do |row, row_index|
          row_class = row_index.even? ? 'bg-blue-50' : 'bg-white'
          content_tag(:tr, class: row_class) do
            row.map.with_index do |cell, cell_index|
              classes = "text-lg px-6 py-4 whitespace-nowrap text-gray-900 #{cell[:class]} text-center align-middle" 
              styles = ''
              if cell_index < fix_to
                classes += ' sticky'
              end
              content_tag(:td, cell[:content], id: cell[:id], class: classes, style: styles)
            end.join.html_safe
          end
        end.join.html_safe
      end
    end
    
    
    
  end
end
