# frozen_string_literal: true

module ClinicManagement
  # CRUD for ServiceLocation (external attendance locations).
  # Internal = NULL service_location_id; external = ServiceLocation record.
  # ESSENTIAL: All actions require multi_service_locations_enabled on current_account.
  class ServiceLocationsController < ApplicationController
    before_action :require_multi_service_locations_enabled!
    before_action :set_service_location, only: %i[show edit update destroy]

    # GET /service_locations
    def index
      @service_locations = ServiceLocation.order(:name).all
      @rows = @service_locations.map.with_index(1) do |loc, index|
        [
          { header: "#", content: index },
          { header: "Nome", content: loc.name },
          { header: "Time Slots", content: loc.time_slots.count },
          { header: "Services", content: loc.services.count },
          { header: "Editar", content: edit_button(loc) },
          { header: "Excluir", content: delete_button(loc) }
        ]
      end
    end

    # GET /service_locations/1
    def show
    end

    # GET /service_locations/new
    def new
      @service_location = ServiceLocation.new
    end

    # GET /service_locations/1/edit
    def edit
    end

    # POST /service_locations
    def create
      @service_location = ServiceLocation.new(service_location_params)

      if @service_location.save
        redirect_to service_locations_path, notice: "Local de atendimento criado com sucesso!"
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /service_locations/1
    def update
      if @service_location.update(service_location_params)
        redirect_to service_locations_path, notice: "Local de atendimento atualizado com sucesso!"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /service_locations/1
    def destroy
      if @service_location.services.any? || @service_location.time_slots.any?
        redirect_to service_locations_path, alert: "Não é possível excluir: existem atendimentos ou horários vinculados."
      else
        @service_location.destroy
        redirect_to service_locations_url, notice: "Local removido com sucesso."
      end
    end

    # POST /service_locations/switch - switch context. Params: location_id (optional, blank = internal, "all" = all externals)
    # Persists in session + cookie so selection survives page refresh.
    def switch
      location_id = params[:location_id].presence
      session[:clinic_service_location_id] = location_id
      cookies.permanent[:clinic_service_location_id] = location_id || ""
      redirect_back fallback_location: clinic_management.services_path
    end

    private

    def require_multi_service_locations_enabled!
      return if current_account&.multi_service_locations_enabled?
      flash[:alert] = "Múltiplos Locais de Atendimento não está habilitado para esta conta."
      redirect_to clinic_management.index_today_path
    end

    def edit_button(loc)
      helpers.link_to(edit_service_location_path(loc)) do
        helpers.content_tag(:i, "", class: "fas fa-edit")
      end
    end

    def delete_button(loc)
      if loc.services.any? || loc.time_slots.any?
        "--"
      else
        helpers.button_to(service_location_path(loc), method: :delete, data: { confirm: "Tem certeza?" }) do
          helpers.content_tag(:i, "", class: "fas fa-trash")
        end
      end
    end

    def set_service_location
      @service_location = ServiceLocation.find(params[:id])
    end

    def service_location_params
      params.require(:service_location).permit(:name, :is_default)
    end
  end
end
