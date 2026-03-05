module ClinicManagement
  class Service < ApplicationRecord
    has_many :appointments, dependent: :destroy
    belongs_to :service_type, optional: true
    belongs_to :service_location, optional: true, class_name: "ClinicManagement::ServiceLocation"

    # Adicione este escopo para buscar serviços futuros
    scope :upcoming, -> { where("date >= ?", Date.today).where(canceled: [false, nil]) }

    # Scope for filtering by service_location_id.
    # nil/blank = internal only; "all" = all externals; id = specific external.
    scope :for_location, ->(location_id) {
      case location_id.to_s
      when "all"
        where.not(service_location_id: nil)
      when ""
        where(service_location_id: nil)
      else
        where(service_location_id: location_id)
      end
    }
  end
end
