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
            
            # Adicionar data attributes para validação de telefone
            if fields.any? { |f| f[:input] == :phone }
              check_url = check_phone_leads_path
              lead_id = record.persisted? ? record.id : 0
              options[:html][:data] ||= {}
              options[:html][:data][:controller] = "lead-phone-validator"
              options[:html][:data][:lead_phone_validator_lead_id_value] = lead_id
              options[:html][:data][:lead_phone_validator_check_url_value] = check_url
            end
            
            form_for(record, options) do |f|
                # Exibir erros de validação do modelo
                if record.errors.any?
                    concat content_tag(:div, class: 'bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative mb-4') do
                      content_tag(:div, class: 'font-bold mb-2') do
                        "#{pluralize(record.errors.count, 'erro impediu', 'erros impediram')} que este #{record.model_name.human.downcase} fosse salvo:"
                      end +
                      content_tag(:ul, class: 'list-disc list-inside') do
                        record.errors.full_messages.map { |msg| concat content_tag(:li, msg) }
                      end
                    end
                end
                fields.each do |field|
                    concat f.label field[:name], 
                                   class: 'block text-gray-700 font-bold mb-2'
                    case field[:type]
                    when 'text'
                        field_options = {
                          value: field[:value],
                          placeholder: field[:placeholder], 
                          class: "#{form_class}"
                        }
                        
                        # Adicionar data attributes para campo de telefone
                        if field[:input] == :phone
                          field_options[:data] = {
                            lead_phone_validator_target: 'phoneInput',
                            action: 'input->lead-phone-validator#validatePhone'
                          }
                        end
                        
                        concat f.text_field field[:input], field_options
                        
                        # Adicionar mensagem de erro para campo de telefone
                        if field[:input] == :phone
                          concat content_tag(:div, '', 
                            class: 'text-red-500 text-sm mt-1 hidden',
                            data: { lead_phone_validator_target: 'errorMessage' }
                          )
                        end
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
                
                # Adicionar target para validação de telefone
                submit_options = { class: 'bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded mt-4' }
                if fields.any? { |field| field[:input] == :phone }
                  submit_options[:data] = { lead_phone_validator_target: 'submitButton' }
                end
                
                concat f.submit submit_label, submit_options
            end
        end
    end
end


class StandardizedFormBuilder < ActionView::Helpers::FormBuilder
    FORM_FIELD_CLASS = 'appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline mb-4'.freeze

    def label(method, text = nil, options = {}, &block)
        return if method.nil?
        options[:class] = "#{options[:class]} block text-gray-700 font-bold mb-2"
        super
    end
    
    def text_field(method, options = {})
        return if method.nil?
        options[:class] = "#{options[:class]} #{FORM_FIELD_CLASS}"
        super
    end

    def text_area(method, options = {})
        return if method.nil?
        options[:class] = "#{options[:class]} #{FORM_FIELD_CLASS}"
        super
    end
    
    def select(method, choices = nil, options = {}, html_options = {}, &block)
        return if method.nil?
        html_options[:class] = "#{html_options[:class]} appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline mb-4"
        super
    end

    def date_field(method, options = {})
        return if method.nil?
        options[:class] = "#{options[:class]} #{FORM_FIELD_CLASS}"
        super
    end   

    def submit(value=nil, options={})
        options[:class] = "#{options[:class]} bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline"
        super
    end
      
end