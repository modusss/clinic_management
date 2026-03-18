module ClinicManagement
  class RegionsController < ApplicationController
    before_action :set_region, only: %i[ show edit update destroy ]

    # GET /regions
    def index
      @regions = Region.active.includes(:invitations)
      
      # Ordenação baseada no parâmetro
      @regions = case params[:sort_by]
      when "invitations_desc"
        @regions.sort_by { |r| -r.invitations.count }
      when "invitations_asc"
        @regions.sort_by { |r| r.invitations.count }
      when "name"
        @regions.sort_by(&:name)
      else
        @regions.order(:name)
      end
      
      @rows = @regions.map.with_index(1) do |reg, index|
        [
          { header: "#", content: index },
          { header: "Nome", content: reg.name },
          { header: "Convites", content: reg.invitations.count },
          { header: "Editar", content: edit_button(reg) },
          { header: "Excluir", content: delete_button(reg) }
        ] 
      end
    end

    # GET /regions/1
    def show
    end

    # GET /regions/new
    def new
      @region = Region.new
    end

    # GET /regions/1/edit
    def edit
    end

    # POST /regions
    def create
      @region = Region.new(region_params)

      if @region.save
        redirect_to regions_path, notice: "Nova região criada com sucesso!"
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /regions/1
    def update
      if @region.update(region_params)
        redirect_to regions_path, notice: "Região editada com sucesso!"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /regions/1
    # When region has invitations: soft delete (set deleted_at) to preserve referential integrity.
    # When no invitations: hard delete.
    def destroy
      if @region.invitations.any?
        @region.soft_delete!
        notice = "Região excluída. Ela não aparecerá mais nas listas, mas os convites existentes permanecem vinculados."
      else
        @region.destroy
        notice = "Região removida com sucesso."
      end
      redirect_to regions_url, notice: notice
    end

    private

      def edit_button(reg)
        helpers.link_to(edit_region_path(reg)) do
          helpers.content_tag(:i, "", class: "fas fa-edit")
        end
      end

      def delete_button(reg)
        helpers.button_to(region_path(reg), method: :delete, data: { confirm: "Tem certeza que deseja excluir esta região?" }) do
          helpers.content_tag(:i, "", class: "fas fa-trash")
        end
      end

      # Use callbacks to share common setup or constraints between actions.
      def set_region
        @region = Region.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def region_params
        params.require(:region).permit(:name)
      end
  end
end
