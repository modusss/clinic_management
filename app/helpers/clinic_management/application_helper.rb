module ClinicManagement
  module ApplicationHelper

    def data_table(headers, data)
      content_tag(:div, class: "flex flex-col") do
        content_tag(:div, class: "-my-2 overflow-x-auto sm:-mx-6 lg:-mx-8") do
          content_tag(:div, class: "py-2 align-middle inline-block min-w-full sm:px-6 lg:px-8") do
            content_tag(:div, class: "shadow overflow-hidden border-b border-gray-200 sm:rounded-lg") do
              content_tag(:table, class: "min-w-full divide-y divide-gray-200") do
                table_header(headers) + table_body(data)
              end
            end
          end
        end
      end
    end
  
    def table_header(headers)
      content_tag(:thead, class: "bg-gray-50") do
        content_tag(:tr) do
          headers.map do |header|
            content_tag(:th, header, scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider")
          end.join.html_safe
        end
      end
    end
  
    def table_body(data)
      content_tag(:tbody, class: "bg-white divide-y divide-gray-200") do
        data.map.with_index do |row, index|
          content_tag(:tr, class: (index.even? ? 'bg-gray-50' : 'bg-white')) do
            row.map do |value|
              content_tag(:td, value, class: "px-6 py-4 whitespace-nowrap text-sm text-gray-900")
            end.join.html_safe
          end
        end.join.html_safe
      end
    end
    
  end
end
