module ClinicManagement
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!

    def authenticate_user!
      if user_signed_in?
        super
      else
        redirect_to new_invitation_path
      end
    end
  end
end
