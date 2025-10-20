module ClinicManagement
    class ServiceTypesController < ApplicationController
      before_action :set_service_type, only: %i[show edit update destroy]
  
      # GET /service_types
      def index
        @rows = ServiceType.where(removed: false).order(:name).map.with_index(1) do |st, index|
          [
            { header: "#", content: index },
            { header: "Nome", content: st.name },
            { header: "Editar", content: edit_button(st) },
            { header: "Excluir", content: delete_button(st) }
          ]
        end
      end
  
      # GET /service_types/1
      def show
      end
  
      # GET /service_types/new
      def new
        @service_type = ServiceType.new
      end
  
      # GET /service_types/1/edit
      def edit
      end
  
      # POST /service_types
      def create
        @service_type = ServiceType.new(service_type_params)
  
        if @service_type.save
          redirect_to service_types_path, notice: "Novo tipo de serviço criado com sucesso!"
        else
          render :new, status: :unprocessable_entity
        end
      end
  
      # PATCH/PUT /service_types/1
      def update
        if @service_type.update(service_type_params)
          redirect_to service_types_path, notice: "Tipo de serviço editado com sucesso!"
        else
          render :edit, status: :unprocessable_entity
        end
      end
  
      # DELETE /service_types/1
      def destroy
        @service_type.update(removed: true)
        redirect_to service_types_url, notice: "Tipo de serviço removido com sucesso. Ele não aparecerá mais nas listas, mas os registros existentes serão mantidos."
      end
  
      private
  
      def edit_button(st)
        helpers.link_to(edit_service_type_path(st)) do
          helpers.content_tag(:i, "", class: "fas fa-edit")
        end
      end
  
      def delete_button(st)
        helpers.button_to(service_type_path(st), method: :delete, data: { confirm: "Tem certeza que deseja remover este tipo de serviço? Ele não aparecerá mais nas listas, mas os registros existentes serão mantidos." }) do
          helpers.content_tag(:i, "", class: "fas fa-trash")
        end
      end
  
      # Use callbacks to share common setup or constraints between actions.
      def set_service_type
        @service_type = ServiceType.find(params[:id])
      end
  
      # Only allow a list of trusted parameters through.
      def service_type_params
        params.require(:service_type).permit(:name)
      end
    end
  end