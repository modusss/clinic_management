module ClinicManagement
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!
    before_action :redirect_referral_users

    private

    def authenticate_user!
      unless user_signed_in?
        super
      end
    end

    def redirect_referral_users
      if current_user.has_referral_role?
        referral_membership = current_user.memberships.find_by(role: "referral")
        referral = Referral.find_by(code: referral_membership.code)
        redirect_to main_app.referral_path(referral) and return
      end
    end

  end
end
