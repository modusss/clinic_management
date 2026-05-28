# frozen_string_literal: true

module ClinicManagement
  # Organization settings (Organização) inside clinic Tailwind layout — Apenas Clínica mode.
  # ESSENTIAL: Membros, Contato, Downloads (leads CSV); no retail-only tabs (cartões, clientes CSV).
  class OrganizationController < ApplicationController
    include OrganizationMembershipActions
    include Devise::Controllers::SignInOut
    include StatusHelper

    before_action :require_manager_above!
    before_action :load_organization_edit_data!, only: [:edit, :create_membership]
    before_action :require_owner_or_admin!, only: [:create_membership, :destroy_membership, :edit_membership, :update_membership]
    before_action :set_membership_user, only: [:edit_membership, :update_membership, :destroy_membership]

    helper_method :membership_role_options

    # GET /clinic_management/organizacao/edit
    def edit
    end

    # PATCH /clinic_management/organizacao
    def update
      if update_organization_contact!
        redirect_to edit_organization_path(tab: "contact"), notice: "Dados salvos com sucesso."
      else
        load_organization_edit_data!
        @active_tab = "contact"
        flash.now[:alert] = current_account.errors.full_messages.join(", ")
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /clinic_management/organizacao/clinic_logo
    def remove_clinic_logo
      @account = current_account
      if @account.clinic_logo.attached?
        @account.clinic_logo.purge
        redirect_to edit_organization_path(tab: "contact"), notice: "Logo da clínica removida com sucesso."
      else
        redirect_to edit_organization_path(tab: "contact"), alert: "Nenhuma logo da clínica para remover."
      end
    end

    # POST /clinic_management/organizacao/cooperadores
    def create_membership
      if create_membership_for_account!
        redirect_to edit_organization_path(tab: "memberships"), notice: @membership_notice
      else
        @active_tab = "memberships"
        flash.now[:alert] = @new_user.errors.full_messages.join(", ")
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /clinic_management/organizacao/cooperadores/:user_id
    def destroy_membership
      if destroy_membership_for_account!(@user)
        redirect_to edit_organization_path(tab: "memberships"), notice: "Cooperador removido com sucesso."
      else
        redirect_to edit_organization_path(tab: "memberships"), alert: @membership_alert || "Não foi possível remover o cooperador."
      end
    end

    # GET /clinic_management/organizacao/cooperadores/:user_id/editar
    def edit_membership
    end

    # PATCH /clinic_management/organizacao/cooperadores/:user_id
    def update_membership
      result = update_membership_for_account!(@user, @membership)
      case result
      when :ok
        redirect_to edit_organization_path(tab: "memberships"), notice: "Cooperador atualizado com sucesso."
      when :blocked_owner
        redirect_to edit_organization_path(tab: "memberships"), alert: @membership_alert
      else
        flash.now[:alert] = @user.errors.full_messages.join(", ")
        render :edit_membership, status: :unprocessable_entity
      end
    end

    # GET /clinic_management/organizacao/leads.csv
    def download_leads_csv
      leads = ClinicManagement::Lead.includes(:leads_conversion).where(leads_conversions: { clinic_management_lead_id: nil })
      send_data generate_lead_data_csv(leads), filename: "leads-#{Date.current}.csv", type: "text/csv"
    end

    private

    def require_manager_above!
      return if helpers.is_manager_above?

      redirect_to clinic_management.index_today_path, alert: "Você não tem permissão para acessar a organização."
    end

    def require_owner_or_admin!
      return if helpers.is_owner? || current_user.admin?

      redirect_to edit_organization_path, alert: "Apenas o proprietário pode gerenciar cooperadores."
    end

    def set_membership_user
      @user = find_account_user!
      @membership = find_membership_for_account!(@user)
    end
  end
end
