module ClinicManagement
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!
    before_action :redirect_referral_users
    skip_before_action :redirect_referral_users, unless: :devise_or_session_or_registration_controller?

    private

    def authenticate_user!
      unless user_signed_in?
        super
      end
    end

    def redirect_referral_users
      unless devise_or_session_or_registration_controller?
        if current_user&.has_referral_role?
          referral_membership = current_user.memberships.find_by(role: "referral")
          referral = Referral.find_by(code: referral_membership.code)
          redirect_to referral_path(referral)
        end
      end
    end    

    def devise_or_session_or_registration_controller?
      is_a?(::Devise::SessionsController) || is_a?(::Devise::RegistrationsController) || is_a?(::DeviseController)
    end

  end
end
