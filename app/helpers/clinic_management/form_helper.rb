module ClinicManagement
    module FormHelper

        def standardized_form_for(record, fields, options = {})
            options[:builder] ||= StandardizedFormBuilder
            options[:html] ||= {}
            options[:html][:class] = "#{options[:html][:class]} bg-white shadow-md rounded px-8 pt-6 pb-8 mb-4"
            form_for(record, options) do |f|
                fields.each do |field|
                    concat f.label field[:name], class: 'block text-gray-700 font-bold mb-2'
                    case field[:type]
                    when 'text'
                        concat f.text_field field[:input], placeholder: field[:placeholder], class: 'appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline'
                    when 'password'
                        concat f.password_field field[:input], placeholder: field[:placeholder], class: 'appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline'
                    when 'text_area'
                        concat f.text_area field[:input], placeholder: field[:placeholder], class: 'appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline'
                    when 'select'
                        concat f.select field[:input], field[:choices], prompt: field[:placeholder], class: 'appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline'
                    # add more cases here for other field types
                    end
                end
                submit_label = f.object.new_record? ? I18n.t('helpers.submit.create', model: f.object.model_name.human) : I18n.t('helpers.submit.update', model: f.object.model_name.human)
                concat f.submit submit_label, class: 'bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded mt-4'
                                
            end
        end

    end
end

class StandardizedFormBuilder < ActionView::Helpers::FormBuilder
    def label(method, text = nil, options = {}, &block)
        return if method.nil?
        options[:class] = "#{options[:class]} block text-gray-700 font-bold mb-2"
        super
    end
    
    def text_field(method, options = {})
        return if method.nil?
        options[:class] = "#{options[:class]} appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline mb-4"
        super
    end

    def text_area(method, options = {})
        return if method.nil?
        options[:class] = "#{options[:class]} appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline mb-4"
        super
    end
    
    def select(method, choices = nil, options = {}, html_options = {}, &block)
        return if method.nil?
        html_options[:class] = "#{html_options[:class]} appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
        super
    end

    def submit(value=nil, options={})
        options[:class] = "#{options[:class]} bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline"
        super
    end
      
end
