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
    # (same normalized phone and same normalized patient name).
    #
    # ESSENTIAL:
    # - Patient identity must come from invitation.patient_name (when present),
    #   not only lead.name.
    # - This allows multiple different patients under the same phone/lead to be
    #   scheduled in the same service without false-positive duplicate errors.
    #
    # @return [void]
    def no_duplicate_patient_same_service
      return if lead_id.blank? || service_id.blank?
      return unless lead.present?

      norm_phone = lead.phone.to_s.gsub(/\D/, "")
      norm_patient_name = (invitation&.patient_name.presence || lead.name).to_s.strip.downcase
      return if norm_patient_name.blank?

      scope = self.class.joins(:lead).includes(:invitation, :lead).where(service_id: service_id)
      scope = scope.where.not(id: id) if persisted?

      # Same patient phone context when available; fallback to same lead for blank phone.
      if norm_phone.present?
        scope = scope.where(
          "REGEXP_REPLACE(COALESCE(clinic_management_leads.phone, ''), '[^0-9]', '', 'g') = ?",
          norm_phone
        )
      else
        scope = scope.where(lead_id: lead_id)
      end

      duplicate_exists = scope.any? do |appointment|
        existing_patient_name = (appointment.invitation&.patient_name.presence || appointment.lead&.name).to_s.strip.downcase
        existing_patient_name == norm_patient_name
      end

      return unless duplicate_exists

      errors.add(:base, I18n.t("clinic_management.appointments.errors.duplicate_patient_same_service",
        default: "Já existe um agendamento para este paciente (mesmo nome e telefone) neste serviço."))
    end
  end
end