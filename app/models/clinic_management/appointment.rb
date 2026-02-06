module ClinicManagement
  # ============================================================================
  # Appointment Model
  # 
  # Represents a scheduled appointment for a patient (Lead) at a specific Service.
  # 
  # TRACKING FIELDS:
  # - registered_by_user_id: User who created/shared the link (effort tracking)
  # - self_booked: Boolean indicating if created via self-booking flow (channel tracking)
  # 
  # SELF-BOOKING CHANNEL:
  # When self_booked=true, the appointment was created by the patient themselves
  # via the self-booking link (sent through WhatsApp). This enables:
  # - Measuring efficiency of the self-booking channel
  # - Tracking conversion rates from automated links
  # - Analyzing patient engagement with the booking flow
  # ============================================================================
  class Appointment < ApplicationRecord
    belongs_to :lead
    belongs_to :service
    belongs_to :invitation, required: true
    belongs_to :registered_by_user, class_name: 'User', optional: true
    has_one :prescription
    
    # Relacionamentos para controle de remarcação
    belongs_to :recapture_by_user, class_name: 'User', optional: true
    belongs_to :recapture_audited_by, class_name: 'User', optional: true
    has_many_attached :recapture_screenshots
    
    # ============================================================================
    # SCOPES FOR SELF-BOOKING ANALYTICS
    # ============================================================================
    scope :self_booked, -> { where(self_booked: true) }
    scope :manually_booked, -> { where(self_booked: [false, nil]) }
    
    # Validações para remarcação com esforço ativo
    validates :recapture_actions, presence: true, if: -> { recapture_origin == 'active_effort' }
    validate :at_least_one_action_selected, if: -> { recapture_origin == 'active_effort' }

    # ESSENTIAL: Prevents duplicate appointments for the same service + same patient (same name + same phone).
    # Covers both: same lead booked twice in same service, and different leads with identical name/phone.
    validate :no_duplicate_patient_same_service
    
    # Callback para definir o usuário atual se não foi especificado
    before_save :set_registered_by_user_fallback, if: -> { registered_by_user_id.blank? && read_attribute(:registered_by_user).blank? }

    # Método helper para exibir o nome do usuário que registrou
    def registered_by_user_name
      if registered_by_user_id.present?
        User.find_by(id: registered_by_user_id)&.name || "Usuário não encontrado"
      else
        read_attribute(:registered_by_user).presence || "Sistema"
      end
    end
    
    # Verifica se é remarcação (existe appointment anterior remarcado do mesmo lead)
    def is_reschedule?
      return false unless lead_id.present?
      
      ClinicManagement::Appointment.where(lead_id: lead_id)
                                   .where(status: 'remarcado')
                                   .where('created_at < ?', created_at || Time.current)
                                   .exists?
    end
    
    # Retorna o appointment anterior que foi remarcado
    def previous_appointment
      return nil unless lead_id.present?
      
      ClinicManagement::Appointment.where(lead_id: lead_id)
                                   .where(status: 'remarcado')
                                   .where('created_at < ?', created_at || Time.current)
                                   .order(created_at: :desc)
                                   .first
    end

    private

    def set_registered_by_user_fallback
      # Fallback para "Sistema" quando não há usuário definido
      write_attribute(:registered_by_user, "Sistema")
    end
    
    def at_least_one_action_selected
      if recapture_actions.blank? || recapture_actions.reject(&:blank?).empty?
        errors.add(:recapture_actions, "deve ter pelo menos uma ação selecionada")
      end
    end

    # Ensures no other appointment exists for the same service with the same patient
    # (same normalized phone and same normalized name). Handles same lead booked twice
    # and different Lead records with duplicate name+phone.
    #
    # @return [void]
    def no_duplicate_patient_same_service
      return if lead_id.blank? || service_id.blank?
      return unless lead.present?

      norm_phone = lead.phone.to_s.gsub(/\D/, "")
      norm_name = lead.name.to_s.strip.downcase

      # Lead ids considered "same patient": same normalized phone and name (includes current lead)
      duplicate_lead_ids = if norm_phone.present? && norm_name.present?
        Lead.where(
          "REGEXP_REPLACE(COALESCE(phone, ''), '[^0-9]', '', 'g') = ? AND LOWER(TRIM(COALESCE(name, ''))) = ?",
          norm_phone, norm_name
        ).pluck(:id)
      else
        [lead_id]
      end

      return if duplicate_lead_ids.empty?

      scope = self.class.where(service_id: service_id, lead_id: duplicate_lead_ids)
      scope = scope.where.not(id: id) if persisted?

      return unless scope.exists?

      errors.add(:base, I18n.t("clinic_management.appointments.errors.duplicate_patient_same_service",
        default: "Já existe um agendamento para este paciente (mesmo nome e telefone) neste serviço."))
    end
  end
end