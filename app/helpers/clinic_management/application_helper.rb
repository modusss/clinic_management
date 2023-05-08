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
