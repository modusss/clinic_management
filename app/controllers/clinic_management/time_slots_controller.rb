module ClinicManagement
  class TimeSlotsController < ApplicationController
    before_action :set_time_slot, only: %i[ show edit update destroy ]

    # GET /time_slots
    def index
      @time_slots = TimeSlot.all
    end

    # GET /time_slots/1
    def show
    end

    # GET /time_slots/new
    def new
      @time_slot = TimeSlot.new
    end

    # GET /time_slots/1/edit
    def edit
    end

    # POST /time_slots
    def create
      day_number = get_day_field(params[:time_slot][:weekday])
      @time_slot = TimeSlot.new(time_only_slot_params)
      @time_slot.weekday = day_number
      if @time_slot.save
        redirect_to @time_slot, notice: "Time slot was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /time_slots/1
    def update
      day_number = get_day_field(params[:time_slot][:weekday])
      @time_slot.weekday = day_number
      if @time_slot.update(time_only_slot_params)
        redirect_to @time_slot, notice: "Time slot was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /time_slots/1
    def destroy
      @time_slot.destroy
      redirect_to time_slots_url, notice: "Time slot was successfully destroyed."
    end

    def available_dates
      @time_slot = TimeSlot.find(params[:id])
      render partial: "clinic_management/services/date_selector", 
             locals: { dates: helpers.next_available_dates(@time_slot) }
    end

    private
      def get_day_field(day)
        case day.downcase
        when "domingo"
          1
        when "segunda-feira"
          2
        when "terça-feira"
          3
        when "quarta-feira"
          4
        when "quinta-feira"
          5
        when "sexta-feira"
          6
        when "sábado"
          7
        end
      end

      # Use callbacks to share common setup or constraints between actions.
      def set_time_slot
        @time_slot = TimeSlot.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def time_slot_params
        params.require(:time_slot).permit(:weekday, :start_time, :end_time)
      end

      def time_only_slot_params
        params.require(:time_slot).permit(:start_time, :end_time)
      end
  end
end
