module ClinicManagement
  class Lead < ApplicationRecord
    
    before_save :format_latitude, :format_longitude, :sanitize_phone

    has_many :invitations, dependent: :destroy
    has_many :appointments, through: :invitations
    has_many :appointments, dependent: :destroy
    has_one :leads_conversion, foreign_key: 'clinic_management_lead_id'
    has_one :customer, through: :leads_conversion
    has_many :lead_interactions, dependent: :destroy
    has_many :lead_page_views, dependent: :destroy
    validates :phone, format: { with: /\A\d{10,11}\z/, message: "deve ter 10 ou 11 dígitos" }, allow_blank: true
    validates :self_booking_token, uniqueness: true, allow_nil: true

    before_destroy :destroy_appointments

    # ============================================================================
    # SELF-BOOKING TOKEN METHODS
    # 
    # These methods enable the patient self-scheduling feature.
    # The token is a secure, unique identifier that allows patients to access
    # a simplified booking flow via a shareable link (e.g., sent via WhatsApp).
    # 
    # ESSENTIAL: Token generation is lazy (on-demand) to avoid generating tokens
    # for leads that will never use the self-booking feature.
    # ============================================================================

    # Generates a new self-booking token if one doesn't exist
    # Uses SecureRandom.urlsafe_base64 for cryptographically secure tokens
    # 
    # @return [String] the self-booking token (existing or newly generated)
    # 
    # @example
    #   lead.generate_self_booking_token!
    #   # => "xK9mN2pQ7vR1wY4z"
    def generate_self_booking_token!
      return self_booking_token if self_booking_token.present?
      
      loop do
        token = SecureRandom.urlsafe_base64(12) # 16-character URL-safe token
        unless ClinicManagement::Lead.exists?(self_booking_token: token)
          update!(self_booking_token: token)
          return token
        end
      end
    end

    # Returns the self-booking token, generating one if needed
    # This is the preferred method for getting the token
    # 
    # @return [String] the self-booking token
    def self_booking_token!
      generate_self_booking_token!
    end

    # Finds a lead by their self-booking token
    # 
    # @param token [String] the self-booking token to search for
    # @return [Lead, nil] the lead with the matching token, or nil if not found
    # 
    # @example
    #   Lead.find_by_self_booking_token("xK9mN2pQ7vR1wY4z")
    #   # => #<ClinicManagement::Lead id: 123, ...>
    def self.find_by_self_booking_token(token)
      return nil if token.blank?
      find_by(self_booking_token: token)
    end

    # Returns the patient's first name (for personalized greetings)
    # Extracts from the most recent invitation's patient_name if available,
    # otherwise falls back to the lead's name
    # 
    # @return [String] the patient's first name
    def patient_first_name
      last_invitation = invitations.order(created_at: :desc).first
      name_to_use = last_invitation&.patient_name || name
      name_to_use&.split&.first || "Paciente"
    end

    # Returns the full patient name from the most recent invitation
    # 
    # @return [String] the patient's full name
    def patient_full_name
      last_invitation = invitations.order(created_at: :desc).first
      last_invitation&.patient_name || name || "Paciente"
    end

    # ============================================================================
    # DISTINCT PATIENTS ASSOCIATED WITH THIS LEAD (PHONE NUMBER)
    # 
    # A single Lead (phone owner) can have multiple patients associated through
    # invitations. For example: Rafael (father, phone owner) with Joana (daughter).
    # 
    # This method returns distinct patients grouped by FIRST NAME (case-insensitive)
    # to handle variations like "Caio da Silva Gomes" vs "Caio da silva".
    # 
    # DEDUPLICATION LOGIC:
    # - "Caio da Silva Gomes" and "Caio da silva" -> same person (same first name)
    # - "João" and "Maria" -> different people
    # 
    # @return [Array<Hash>] array of {first_name:, full_name:} hashes, unique by first_name
    # 
    # @example
    #   lead.distinct_patients
    #   # => [{first_name: "Rafael", full_name: "Rafael Paiva Santos"},
    #   #     {first_name: "Joana", full_name: "Joana da Silva"}]
    # ============================================================================
    def distinct_patients
      # Collect all patient names from invitations
      patient_names = invitations.pluck(:patient_name).compact
      
      # Add the lead's own name if present
      patient_names << name if name.present?
      
      # Deduplicate by first name (case-insensitive, accent-insensitive)
      patients_by_first_name = {}
      
      patient_names.each do |full_name|
        next if full_name.blank?
        
        # Extract first name and normalize
        first_name = full_name.split.first&.strip
        next if first_name.blank?
        
        # Use downcased first name as key for deduplication
        key = normalize_name_for_comparison(first_name)
        
        # Keep the most complete version (longest full name)
        if patients_by_first_name[key].nil? || full_name.length > patients_by_first_name[key][:full_name].length
          patients_by_first_name[key] = {
            first_name: first_name.capitalize,
            full_name: full_name.strip
          }
        end
      end
      
      # Return sorted by first name
      patients_by_first_name.values.sort_by { |p| p[:first_name].downcase }
    end

    # Returns the lead owner's first name (the phone owner, not patients)
    # This should be used for the initial greeting
    # 
    # @return [String] the lead owner's first name
    def owner_first_name
      name&.split&.first || "Paciente"
    end

    # Checks if this lead has multiple distinct patients
    # 
    # @return [Boolean] true if more than one patient is associated
    def has_multiple_patients?
      distinct_patients.count > 1
    end

    # Normalizes a name for comparison purposes
    # Removes accents, converts to lowercase
    # 
    # @param name [String] the name to normalize
    # @return [String] normalized name
    def normalize_name_for_comparison(name)
      return "" if name.blank?
      
      # Remove accents and downcase
      I18n.transliterate(name.downcase)
    rescue
      name.downcase
    end

    # after_create :merge_with_duplicate_leads, if: :phone?

    def destroy_appointments
      appointments.destroy_all
    end

    def test_dms_to_dec(coordinate, type)
      dms_to_dec(coordinate, type)
    end

    # Métodos para estatísticas rápidas
    def total_interactions
      lead_interactions.count
    end
    
    def interactions_by_user(user)
      lead_interactions.where(user: user).count
    end

    # Métodos para WhatsApp status
    def has_whatsapp?
      !no_whatsapp
    end

    def toggle_whatsapp_status!
      update!(no_whatsapp: !no_whatsapp)
    end

    private

    def sanitize_phone
      return unless phone.present?
      
      # Remove todos os caracteres não numéricos (parênteses, espaços, hífens, etc.)
      self.phone = phone.gsub(/\D/, '')
      
      # Log para debug (opcional - pode ser removido em produção)
      Rails.logger.debug "Telefone sanitizado: #{phone_was} -> #{phone}" if phone_changed?
    end

    def self.search_by_name_or_phone(query)
      if query.present?
        # Check if the query contains any digits
        contains_digits = query.match?(/\d/)
        
        if contains_digits
          # If query contains digits, prioritize phone search
          normalized_phone = query.gsub(/\D/, '')
          
          # Remove o prefixo +55 se existir
          normalized_phone = normalized_phone.sub(/^55/, '') if normalized_phone.start_with?('55')
          
          # Create two versions of the phone number - with and without the 9 prefix
          # First, identify if there's likely a DDD code (first 2 digits)
          if normalized_phone.length >= 10
            # Assume first 2 digits are DDD
            ddd = normalized_phone[0..1]
            rest_of_number = normalized_phone[2..-1]
            
            # Create version with 9 prefix (if not already there)
            with_9 = rest_of_number.start_with?('9') ? rest_of_number : "9#{rest_of_number}"
            
            # Create version without 9 prefix (if it's there)
            without_9 = rest_of_number.start_with?('9') ? rest_of_number[1..-1] : rest_of_number
            
            # Search for both versions
            where("REGEXP_REPLACE(phone, '[^0-9]', '', 'g') LIKE :with_9_pattern OR REGEXP_REPLACE(phone, '[^0-9]', '', 'g') LIKE :without_9_pattern", 
                  with_9_pattern: "%#{ddd}#{with_9}%", 
                  without_9_pattern: "%#{ddd}#{without_9}%")
          else
            # If the number is too short to have DDD, just do a simple search
            where("phone ILIKE :phone_query OR REGEXP_REPLACE(phone, '[^0-9]', '', 'g') ILIKE :normalized_phone", 
                  phone_query: "%#{query}%",
                  normalized_phone: "%#{normalized_phone}%")
          end
        else
          # If query doesn't contain digits, search by name only
          where("unaccent(name) ILIKE unaccent(?) ", "%#{query}%") 
        end
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

    def merge_with_duplicate_leads
      # Buscar outros leads com o mesmo telefone (exceto este)
      duplicate_leads = ClinicManagement::Lead
        .where(phone: phone)
        .where.not(id: id)
        .order(:created_at)
      
      return if duplicate_leads.empty?
      
      Rails.logger.info "Lead #{id} encontrou #{duplicate_leads.count} duplicatas. Iniciando merge..."
      
      # Este lead é o mais novo, então mesclar nos mais antigos
      oldest_lead = duplicate_leads.first
      
      # Transferir dados deste lead para o mais antigo
      self.invitations.update_all(lead_id: oldest_lead.id)
      self.appointments.update_all(lead_id: oldest_lead.id)
      
      if self.leads_conversion.present?
        self.leads_conversion.update!(clinic_management_lead_id: oldest_lead)
      end
      
      # Atualizar informações do lead mais antigo se necessário
      update_attrs = {}
      update_attrs[:name] = self.name if oldest_lead.name.blank? && self.name.present?
      update_attrs[:address] = self.address if oldest_lead.address.blank? && self.address.present?
      update_attrs[:converted] = true if !oldest_lead.converted && self.converted
      
      oldest_lead.update_columns(update_attrs) if update_attrs.any?
      
      # Deletar este lead (o mais novo)
      self.destroy!
      
      Rails.logger.info "Lead #{id} foi mesclado com lead #{oldest_lead.id}"
    end
  end
end
