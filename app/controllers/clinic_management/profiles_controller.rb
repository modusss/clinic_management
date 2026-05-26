# frozen_string_literal: true

module ClinicManagement
  # User profile edit inside the clinic engine layout (Tailwind).
  # ESSENTIAL: Primary entry for "Apenas Clínica" mode — avoids main app Materialize layout.
  class ProfilesController < ApplicationController
    include Devise::Controllers::SignInOut

    before_action :set_user

    # GET /clinic_management/perfil/edit
    def edit
    end

    # PATCH /clinic_management/perfil
    def update
      if update_user(@user)
        bypass_sign_in(@user) if password_changed?
        redirect_to edit_profile_path, notice: "Dados atualizados com sucesso."
      else
        flash.now[:alert] = "Não foi possível atualizar seus dados. Verifique os campos."
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = current_user
    end

    def password_changed?
      user_params[:password].present?
    end

    def user_params
      params.require(:user).permit(
        :name,
        :email,
        :phone_prefix,
        :password,
        :password_confirmation,
        :current_password
      )
    end

    # Mirrors Users::RegistrationsController#update_resource (host app).
    def update_user(user)
      attrs = user_params.to_h
      if attrs["current_password"].present?
        user.update_with_password(attrs)
      else
        attrs.delete("current_password")
        attrs.delete("password") if attrs["password"].blank?
        attrs.delete("password_confirmation") if attrs["password_confirmation"].blank?
        user.update_without_password(attrs)
      end
    end
  end
end
