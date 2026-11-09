require "csv"

module ClinicManagement
  module Analytics
    # Spreadsheet-friendly aggregate export; intentionally excludes patient identities.
    class CsvExport
      def initialize(analytics, start_date:, end_date:, filters: {})
        @analytics = analytics
        @start_date = start_date
        @end_date = end_date
        @filters = filters
      end

      def call
        "\uFEFF" + CSV.generate(col_sep: ";") do |csv|
          csv << ["Inteligência de Atendimentos", @start_date.iso8601, @end_date.iso8601]
          @filters.each { |label, value| csv << [safe_cell(label), safe_cell(value.to_s)] }
          csv << ["Indicador", "Valor"]
          %i[patients attended exams sessions].each do |field|
            csv << [label_for(field), @analytics[field]]
          end
          if @analytics[:show_sales]
            csv << ["Compradores", @analytics[:sales]]
            csv << ["Faturamento atribuído", @analytics[:sales_amount]]
          end

          { "Dias da semana" => @analytics[:days], "Turnos" => @analytics[:shifts],
            "Horários" => @analytics[:hours], "Regiões" => @analytics[:regions] }.each do |title, rows|
            csv << []
            csv << [title]
            columns = %i[label patients attended exams sessions]
            columns += %i[sales sales_amount] if @analytics[:show_sales]
            csv << columns.map { |column| label_for(column) }
            rows.each { |row| csv << columns.map { |column| safe_cell(row[column]) } }
          end
          if @analytics[:show_sales] && (geography = @analytics[:customer_geography])
            csv << []
            csv << ["Clientes identificados", geography[:customers]]
            csv << ["Clientes com bairro", geography[:with_district]]
            csv << ["Clientes sem bairro", geography[:without_district]]
            geographic_sections = {
              "Bairros dos clientes" => [geography[:districts], %i[label customers appointments attended exams sales sales_amount]],
              "Região do convite x bairro do cliente" => [geography[:crossings], %i[origin label customers appointments attended exams sales sales_amount]]
            }
            geographic_sections.each do |title, (rows, columns)|
              csv << []
              csv << [title]
              csv << columns.map { |column| label_for(column) }
              rows.each { |row| csv << columns.map { |column| safe_cell(row[column]) } }
            end
          end
        end
      end

      private

      def label_for(field)
        {
          label: "Categoria", patients: "Agendados", attended: "Compareceram",
          exams: "Receitas", sessions: "Sessões", sales: "Compradores",
          sales_amount: "Faturamento (R$)", customers: "Clientes únicos",
          appointments: "Marcações", origin: "Região do convite"
        }.fetch(field)
      end

      # ESSENTIAL: Neutralize spreadsheet formulas from user-defined region names.
      def safe_cell(value)
        return value unless value.is_a?(String)

        value.match?(/\A\s*[=+\-@\t\r]/) ? "'#{value}" : value
      end
    end
  end
end
