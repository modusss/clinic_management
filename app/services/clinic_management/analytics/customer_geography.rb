module ClinicManagement
  module Analytics
    # Compares the invitation region with the linked commercial customer's district.
    # ESSENTIAL: Customer districts come exclusively from LeadsConversion -> Customer,
    # never inferred from Lead.address or invitation region. A customer is counted
    # once per district, while repeat examinations remain separate activity.
    class CustomerGeography
      UNKNOWN_DISTRICT = "Bairro não informado".freeze

      def initialize(appointments:, sales_by_appointment:, include_sales:)
        @appointments = appointments
        @sales_by_appointment = sales_by_appointment
        @include_sales = include_sales
      end

      def call
        return empty_result unless @include_sales

        conversions = LeadsConversion.includes(:customer)
                                     .where(clinic_management_lead_id: @appointments.map(&:lead_id).uniq)
                                     .index_by(&:clinic_management_lead_id)
        districts = {}
        crossings = {}
        all_customers = Set.new
        known_customers = Set.new

        @appointments.each do |appointment|
          customer = conversions[appointment.lead_id]&.customer
          next unless customer

          all_customers << customer.id
          label = district_label(customer.district)
          known_customers << customer.id unless label == UNKNOWN_DISTRICT
          district_key = normalized_key(label)
          district = (districts[district_key] ||= empty_group(label))
          invitation_region = appointment.invitation&.region&.name.presence || "Sem região"
          crossing = (crossings[[invitation_region, district_key]] ||= empty_group(label).merge(origin: invitation_region))

          [district, crossing].each do |group|
            group[:customer_ids] << customer.id
            group[:appointments] += 1
            group[:attended] += 1 if appointment.attendance?
            group[:exams] += 1 if appointment.prescription.present?
            @sales_by_appointment.fetch(appointment.id, []).each do |sale|
              next unless group[:order_ids].add?(sale[:order_id])

              group[:buyer_ids] << sale[:customer_id]
              group[:sales_amount] += sale[:amount]
            end
          end
        end

        {
          customers: all_customers.size,
          with_district: known_customers.size,
          without_district: (all_customers - known_customers).size,
          districts: districts.values.map { |group| finalize(group) }.sort_by { |group| [-group[:sales_amount], -group[:customers], group[:label]] },
          crossings: crossings.values.map { |group| finalize(group) }.sort_by { |group| [-group[:customers], group[:origin], group[:label]] }
        }
      end

      private

      def empty_result
        { customers: 0, with_district: 0, without_district: 0, districts: [], crossings: [] }
      end

      def empty_group(label)
        {
          label: label, customer_ids: Set.new, appointments: 0, attended: 0,
          exams: 0, buyer_ids: Set.new, order_ids: Set.new, sales_amount: 0.to_d
        }
      end

      # Normalize casing, whitespace and accents for grouping, not for persistence.
      def normalized_key(label)
        I18n.transliterate(label).downcase.squish
      end

      def district_label(value)
        label = value.to_s.squish
        label.present? ? label.titleize : UNKNOWN_DISTRICT
      end

      def finalize(group)
        group[:customers] = group.delete(:customer_ids).size
        group[:sales] = group.delete(:buyer_ids).size
        group.delete(:order_ids)
        group
      end
    end
  end
end
