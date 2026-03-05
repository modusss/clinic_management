module ClinicManagement
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!
    before_action :redirect_referral_users
    before_action :redirect_doctor_users
    before_action :set_referral
    before_action :set_company_info

    private

    def set_referral
      code = current_user.memberships.last&.code
      @current_referral = code.present? ? Referral.find_by(code: code) : nil
    end

    def set_company_info
      @company_contact = current_account&.account_contact_info
      @company_name = @company_contact&.company_name
    end
    
    # Helper para acessar a conta do usuário atual
    def current_account
      @current_account ||= current_user&.accounts&.first
    end
    helper_method :current_account

    # ESSENTIAL: Service location context for multi-region support.
    # nil = internal (default); ServiceLocation = external.
    # Persists in session + cookie so selection survives page refresh.
    # When multi_service_locations_enabled is false: always returns nil (internal) so cookie/session
    # do not leak external context; filters (Services, Prescriptions, etc.) show only internal.
    # When doctor: only returns locations they're allowed to use (allowed_service_locations).
    def current_service_location_id
      return nil unless current_account&.multi_service_locations_enabled?
      id = session[:clinic_service_location_id].presence || cookies[:clinic_service_location_id].presence
      session[:clinic_service_location_id] = id if id.present? && session[:clinic_service_location_id].blank?

      # ESSENTIAL: Doctors can only see locations they're associated with.
      if doctor_user?
        return nil if id.blank? # internal is always allowed
        unless current_user.allowed_service_locations.exists?(id)
          session[:clinic_service_location_id] = nil
          cookies.delete(:clinic_service_location_id)
          return nil
        end
      end

      id
    end
    helper_method :current_service_location_id

    # ESSENTIAL: Whether current user is a doctor (Membership.role == "doctor").
    def doctor_user?
      helpers.current_membership&.role == "doctor"
    end
    helper_method :doctor_user?

    # ESSENTIAL: For doctors, returns [["Interno", ""], ["Local X", id], ...] for location selector.
    # Only includes locations the doctor is allowed to use.
    def doctor_service_location_options
      return [] unless doctor_user? && current_account&.multi_service_locations_enabled?
      internal = [["Interno", ""]]
      allowed = current_user.allowed_service_locations.order(:name).map { |loc| [loc.name, loc.id.to_s] }
      internal + allowed
    end
    helper_method :doctor_service_location_options

    def current_service_location
      return nil if current_service_location_id.blank?
      @current_service_location ||= ServiceLocation.find_by(id: current_service_location_id)
    end
    helper_method :current_service_location

    # ESSENTIAL: Whether account allows multiple service locations (internal + externals).
    # When false, only "Interno" is shown in invitation/new and other location selectors.
    def multi_service_locations_enabled?
      current_account&.multi_service_locations_enabled?
    end
    helper_method :multi_service_locations_enabled?

    # ESSENTIAL: Options for lead_message form service_location select.
    # [["Interno", "internal"], ["Local X", id], ...]. "internal" maps to nil (global for internal).
    # Used when multi_service_locations_enabled - default comes from current_service_location_id.
    def lead_message_service_location_options
      return [] unless multi_service_locations_enabled?
      internal = [["Interno", "internal"]]
      locations = ServiceLocation.order(:name).map { |loc| [loc.name, loc.id.to_s] }
      internal + locations
    end
    helper_method :lead_message_service_location_options

    # Default value for lead_message form service_location_id.
    # When navbar has "Todos" (all): returns "" (prompt, validation required).
    # When navbar has "Interno": returns "internal".
    # When navbar has specific location: returns that id.
    def lead_message_default_service_location_id
      return nil unless multi_service_locations_enabled?
      id = current_service_location_id
      return "" if id.to_s == "all"
      return "internal" if id.blank?
      id.to_s
    end
    helper_method :lead_message_default_service_location_id

    # ESSENTIAL: When navbar is "Todos externos", form must require location selection.
    def require_service_location_selection?
      multi_service_locations_enabled? && current_service_location_id.to_s == "all"
    end
    helper_method :require_service_location_selection?

    def authenticate_user!
      unless user_signed_in?
        super
      end
    end

    def redirect_referral_users
      unless devise_or_session_or_registration_controller?
        membership = helpers.current_membership
        if membership.role == "referral"
          referral = Referral.find_by(code: membership.code)
          redirect_to main_app.referral_path(referral)
        end
      end
    end    

    def redirect_doctor_users
      unless devise_or_session_or_registration_controller?
        if helpers.current_membership&.role == "doctor"
          redirect_to clinic_management.index_today_path
        end
      end
    end

    def devise_or_session_or_registration_controller?
      is_a?(::Devise::SessionsController) || is_a?(::Devise::RegistrationsController) || is_a?(::DeviseController)
    end

  end
end
