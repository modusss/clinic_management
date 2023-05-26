module ClinicManagement
    module FormHelper

        def standardized_form_for(record, fields, options = {})
            if fields.empty?
              return content_tag(:p, 'Não houve resultados.', class: 'text-red-600')
            end

            form_class = 'appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline'.freeze
            options[:builder] ||= StandardizedFormBuilder
            options[:html] ||= {}
            options[:html][:class] = "#{options[:html][:class]} bg-white shadow-md rounded px-8 pt-6 pb-8 mb-4"
            form_for(record, options) do |f|
                fields.each do |field|
                    concat f.label field[:name], 
                                   class: 'block text-gray-700 font-bold mb-2'
                    case field[:type]
                    when 'text'
                        concat f.text_field field[:input], 
                                            value: field[:value],
                                            placeholder: field[:placeholder], 
                                            class: "#{form_class}"
                    when 'password'
                        concat f.password_field field[:input], 
                                                value: field[:value],
                                                placeholder: field[:placeholder], 
                                                class: "#{form_class}"
                    when 'text_area'
                        concat f.text_area field[:input], 
                                           value: field[:value],
                                           placeholder: field[:placeholder], 
                                           class: "#{form_class}"
                    when 'select'
                        concat f.select field[:input], 
                                        field[:options], 
                                        prompt: "Selecione um dia", 
                                        class: "#{form_class}", 
                                        selected: field[:selected]
                    when 'date'
                        concat f.date_field field[:input], 
                                            value: field[:value],
                                            placeholder: field[:placeholder], 
                                            class: "#{form_class}" + ' mb-4'       
                    when 'time'
                        concat f.time_field field[:input],
                                            label: false,
                                            placeholder: field[:placeholder],
                                            value: field[:value],
                                            class: 'appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline mb-4'
                    # add more cases here for other field types
                    end
                end
                submit_label = f.object.new_record? ? I18n.t('helpers.submit.create', model: f.object.model_name.human) : I18n.t('helpers.submit.update', model: f.object.model_name.human)
                concat f.submit submit_label, class: 'bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded mt-4'
            end
        end
    end
end
