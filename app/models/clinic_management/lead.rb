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
    
      # Insere o ponto decimal na posição correta
      decimal_value = cleaned_value.insert(2, '.').to_f
    
      # Verifica se é latitude e se o valor é positivo e o torna negativo
      decimal_value *= -1 if decimal_value > 0
    
      decimal_value
    end

  end
end
