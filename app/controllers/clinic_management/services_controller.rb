module ClinicManagement
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[ show edit update destroy ]

    # GET /services
    def index
      @services = ClinicManagement::Service.all
    end

    # GET /services/1
    def show
    end

    # GET /services/new
    def new
      @service = Service.new
    end

    # GET /services/1/edit
    def edit
    end

    # POST /services
    def create
      @service = Service.new(service_params)

      if @service.save
        redirect_to @service, notice: "Service was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /services/1
    def update
      if @service.update(service_params)
        redirect_to @service, notice: "Service was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /services/1
    def destroy
      @service.destroy
      redirect_to services_url, notice: "Service was successfully destroyed."
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_service
        @service = Service.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def service_params
        params.require(:service).permit(:weekday, :start_time, :end_time, :date, :time_slot_id)
      end
  end
end
