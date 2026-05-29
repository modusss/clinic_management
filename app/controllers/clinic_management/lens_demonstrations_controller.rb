module ClinicManagement
  # Exposes the lens demonstration experience inside clinic_management for doctors.
  # ESSENTIAL: This controller reuses the main app template and explicitly hides
  # the "campos de visão" tab/content for the clinical explanation workflow.
  class LensDemonstrationsController < ApplicationController
    skip_before_action :redirect_doctor_users, only: [:show]
    before_action :ensure_doctor_user!
    before_action :mark_clinic_lens_demo_layout

    def show
      @hide_field_of_view_tab = true
      render template: "lens_demonstrations/show"
    end

    private

    def ensure_doctor_user!
      return if doctor_user?

      redirect_to clinic_management.index_today_path, alert: "Acesso disponível apenas para doutores."
    end

    # ESSENTIAL: Enables full-width shell in clinic layout (mirrors main app .custom-container).
    def mark_clinic_lens_demo_layout
      @clinic_lens_demo_layout = true
    end
  end
end
