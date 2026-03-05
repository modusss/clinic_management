module ClinicManagement
  class TimeSlotsController < ApplicationController
    before_action :set_time_slot, only: %i[ show edit update destroy ]

    # GET /time_slots
    def index
      @time_slots = TimeSlot.for_location(current_service_location_id)
      # Group by location: title above, cards below (avoids repeating "Local" in each card)
      if current_service_location_id.to_s == "all"
        @time_slots_grouped = @time_slots.group_by(&:service_location).to_a
        @time_slots_grouped.sort_by! { |loc, _| loc&.name.to_s }
      else
        # Single location (internal or specific external): one section with location as title
        loc = current_service_location_id.present? ? current_service_location : nil
        @time_slots_grouped = @time_slots.any? ? [[loc, @time_slots]] : []
      end
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
    # When "all" externals selected: create one TimeSlot per ServiceLocation (shared across all externals).
    # Otherwise: create single TimeSlot for the selected location.
    def create
      day_number = get_day_field(params[:time_slot][:weekday])
      loc_id = current_service_location_id

      if loc_id.to_s == "all"
        # Create one TimeSlot per external ServiceLocation that does NOT already have this slot (weekday + start_time + end_time).
        locations = ServiceLocation.order(:name)
        if locations.empty?
          redirect_to time_slots_path, alert: "Nenhum local externo cadastrado. Cadastre em Locais de Atendimento."
          return
        end
        # Parse times via model to match DB format (params may come as string or hash)
        base_slot = TimeSlot.new(time_only_slot_params)
        base_slot.weekday = day_number
        start_t = base_slot.start_time
        end_t = base_slot.end_time
        created_count = 0
        skipped_count = 0
        errors = []
        locations.each do |loc|
          existing = TimeSlot.find_by(weekday: day_number, start_time: start_t, end_time: end_t, service_location_id: loc.id)
          if existing
            skipped_count += 1
            next
          end
          slot = TimeSlot.new(time_only_slot_params)
          slot.weekday = day_number
          slot.service_location_id = loc.id
          if slot.save
            created_count += 1
          else
            errors.concat(slot.errors.full_messages)
          end
        end
        if errors.any?
          @time_slot = TimeSlot.new(time_only_slot_params)
          @time_slot.weekday = day_number
          flash.now[:alert] = errors.uniq.join("; ")
          render :new, status: :unprocessable_entity
        elsif created_count.zero? && skipped_count > 0
          redirect_to time_slots_path, notice: "Este horário já existe em todos os locais externos (#{skipped_count} locais). Nenhum novo criado."
        else
          msg = ["Horários criados para #{created_count} local(is) externo(s)."]
          msg << "#{skipped_count} já existiam." if skipped_count > 0
          redirect_to time_slots_path, notice: msg.join(" ")
        end
      else
        @time_slot = TimeSlot.new(time_only_slot_params)
        @time_slot.weekday = day_number
        @time_slot.service_location_id = loc_id.presence
        if @time_slot.save
          redirect_to time_slots_path, notice: "Horário criado com sucesso."
        else
          render :new, status: :unprocessable_entity
        end
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
        params.require(:time_slot).permit(:weekday, :start_time, :end_time, :service_location_id)
      end

      def time_only_slot_params
        params.require(:time_slot).permit(:start_time, :end_time)
      end
  end
end
