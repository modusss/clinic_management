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

    def data_table(rows, fix_to = nil)
      content_tag(:div, class: "flex", data: { controller: "scroll-sync" }) do
        if fix_to
          fixed_rows = rows.map { |row| row.take(fix_to) }
          scrollable_rows = rows.map { |row| row.drop(fix_to) }
    
          table_wrapper("fixed", fixed_rows, "shadow overflow-hidden border-b border-gray-200 sm:rounded-lg", "position: relative; z-index: 2;") +
            table_wrapper("scrollable", scrollable_rows, "shadow overflow-hidden border-b border-gray-200 sm:rounded-lg", "position: relative; z-index: 1;", 'overflow-x-auto')
        else
          table_wrapper("scrollable", rows, "shadow overflow-hidden border-b border-gray-200 sm:rounded-lg")
        end
      end
    end
    
    def table_wrapper(id, rows, inner_classes, style = nil, outer_overflow_class = '')
      content_tag(:div, class: "-my-2 #{outer_overflow_class} sm:-mx-6 lg:-mx-8", data: { scroll_sync_target: id }, style: style) do
        content_tag(:div, class: "py-2 align-middle inline-block min-w-full sm:px-6 lg:px-8") do
          content_tag(:div, class: inner_classes) do
            content_tag(:table, class: "min-w-full divide-y divide-gray-200") do
              table_header(rows.first.map { |cell| cell[:header] }) + table_body(rows)
            end
          end
        end
      end
    end
    
    def table_header(headers)
      content_tag(:thead, class: "bg-gray-50") do
        content_tag(:tr, style: "height: 60px;") do
          headers.map do |header|
            content_tag(:th, header, scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider")
          end.join.html_safe
        end
      end
    end
    
    def table_body(rows)
      content_tag(:tbody, class: "bg-white divide-y divide-gray-200") do
        rows.map.with_index do |row, row_index|
          content_tag(:tr, class: (row_index.even? ? 'bg-gray-50' : 'bg-white')) do
            row.map.with_index do |cell, cell_index|
              content_tag(:td, cell[:content], id: cell[:id], class: "px-6 py-4 whitespace-nowrap text-sm text-gray-900 #{cell[:class]} column-#{cell_index}")
            end.join.html_safe
          end
        end.join.html_safe
      end
    end
    
  
  end
end
