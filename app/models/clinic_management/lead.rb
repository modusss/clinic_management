module ClinicManagement
  class Lead < ApplicationRecord
    before_save :format_latitude, :format_longitude

    has_many :invitations, dependent: :destroy
    has_many :appointments, through: :invitations
    has_many :appointments, dependent: :destroy
    has_one :leads_conversion, foreign_key: 'clinic_management_lead_id'
    has_one :customer, through: :leads_conversion
    validates :phone, format: { with: /\A\d{10,11}\z/, message: "deve ter 10 ou 11 dígitos" }, allow_blank: true

    before_destroy :destroy_appointments

    def destroy_appointments
      appointments.destroy_all
    end

    private

    def self.search_by_name_or_phone(query)
      where("name ILIKE :query OR phone ILIKE :query", query: "%#{query}%")
    end

    def format_latitude
      self.latitude = parse_coordinate(latitude)
    end
  
    def format_longitude
      self.longitude = parse_coordinate(longitude)
    end
  
    def parse_coordinate(value)
      return nil if value.blank?
  
      # Remove os caracteres não numéricos
      cleaned_value = value.to_s.gsub(/[^0-9]/, '')
  
      # Extrai os componentes da coordenada
      degrees = cleaned_value[0..1].to_i
      minutes = cleaned_value[2..3].to_i
      seconds = cleaned_value[4..5].to_i
      decimals = cleaned_value[6..-1].to_i
  
      # Calcula a coordenada decimal
      decimal_value = degrees + (minutes / 60.0) + (seconds / 3600.0) + (decimals / 3600.0 / (10 ** (cleaned_value.length - 6)))
  
      # Verifica se o valor é negativo
      decimal_value *= -1 if value.to_s.start_with?('-')
  
      decimal_value
    end

  end
end
