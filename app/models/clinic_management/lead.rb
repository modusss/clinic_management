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
      if query.present?
        normalized_query = query.gsub(/[^0-9A-Za-z]/, '')
        normalized_phone = query.gsub(/\D/, '')
        
        # Remove o prefixo +55 se existir
        normalized_phone = normalized_phone.sub(/^55/, '') if normalized_phone.start_with?('55')
        
        where("name ILIKE :query OR phone ILIKE :phone_query OR REGEXP_REPLACE(phone, '[^0-9]', '', 'g') ILIKE :normalized_phone", 
              query: "%#{normalized_query}%", 
              phone_query: "%#{query}%",
              normalized_phone: "%#{normalized_phone}%")
      else
        all
      end
    end

    def format_latitude
      self.latitude = convert_to_decimal(latitude, :lat) if latitude.present?
    end

    def format_longitude
      self.longitude = convert_to_decimal(longitude, :lon) if longitude.present?
    end

    def convert_to_decimal(coordinate, type)
      coordinate = coordinate.to_s.split(".0").first
      if coordinate.to_s.match?(/\A-?\d+\.\d+\z/)
        # O valor já está no formato decimal
        decimal = coordinate.to_f
        # Adicionar sinal negativo se não houver
        decimal *= -1 unless decimal < 0
        decimal
      else
        # O valor está no formato DMS, fazer a conversão
        dms_to_dec(coordinate.to_s, type)
      end
    end

    def dms_to_dec(coordinate, type)
      # Extrair graus, minutos e segundos da string de entrada
      degrees = coordinate[0..1].to_i
      minutes = coordinate[2..3].to_i
      seconds = coordinate[4..9].to_f / 100

      # Converter para decimal
      decimal = degrees + minutes / 60.0 + seconds / 3600.0

      # Adicionar sinal negativo se for latitude (S) ou longitude (W)
      decimal *= -1 if type == :lat || type == :lon

      decimal
    end
  end
end
