module ClinicManagement
  class RegionsController < ApplicationController
    before_action :set_region, only: %i[ show edit update destroy ]

    # GET /regions
    def index
      @regions = Region.all
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
        redirect_to @region, notice: "Region was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /regions/1
    def update
      if @region.update(region_params)
        redirect_to @region, notice: "Region was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /regions/1
    def destroy
      @region.destroy
      redirect_to regions_url, notice: "Region was successfully destroyed."
    end

    private
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
