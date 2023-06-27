module ClinicManagement
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!
    before_action :redirect_referral_users
    before_action :set_today_list

    private

    def set_today_list
      @today_service = Service.find_by(date: Date.today)
    end

    def authenticate_user!
      unless user_signed_in?
        super
      end
    end

    def redirect_referral_users
      unless devise_or_session_or_registration_controller?
        if helpers.referral? current_user
          membership = helpers.current_membership
          referral = Referral.find_by(code: membership.code)
          redirect_to main_app.referral_path(referral)
        end
      end
    end    

    def devise_or_session_or_registration_controller?
      is_a?(::Devise::SessionsController) || is_a?(::Devise::RegistrationsController) || is_a?(::DeviseController)
    end

  end
end
