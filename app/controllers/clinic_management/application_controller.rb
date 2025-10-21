module ClinicManagement
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!
    before_action :redirect_referral_users
    before_action :redirect_doctor_users
    before_action :set_referral

    private

    def set_referral
      @current_referral = Referral.find_by(code: current_user.memberships.last.code)
    end
    
    # Helper para acessar a conta do usuário atual
    def current_account
      @current_account ||= current_user&.accounts&.first
    end
    helper_method :current_account

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
