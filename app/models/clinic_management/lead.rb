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

    def test_dms_to_dec(coordinate, type)
      dms_to_dec(coordinate, type)
    end

    private

    def self.search_by_name_or_phone(query)
      where("name ILIKE :query OR phone ILIKE :query", query: "%#{query}%")
    end

    def format_latitude
      self.latitude = dms_to_dec(latitude.to_s, :lat) if latitude.present?
    end

    def format_longitude
      self.longitude = dms_to_dec(longitude.to_s, :lon) if longitude.present?
    end

    def dms_to_dec(coordinate, type)
      coordinate = coordinate.split(".0").first
      # check if there is a negative sign
      negative = coordinate.include?("-")
      if negative
        coordinate
      else
        # Extrair graus, minutos e segundos da string de entrada
        degrees = coordinate[0..1].to_i
        minutes = coordinate[2..3].to_i
        seconds = coordinate[4..8].to_f / 1000
      
        # Converter para decimal
        decimal = degrees + minutes/60.0 + seconds/3600.0
      
        # Adicionar sinal negativo se for latitude (S) ou longitude (O)
        decimal *= -1 if type == :lat || type == :lon
      
        decimal
      end
    end
  end
end
