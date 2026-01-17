# frozen_string_literal: true

module ClinicManagement
  # ============================================================================
  # SelfBookingsController - Patient Self-Scheduling Flow
  # 
  # PURPOSE: Allows patients to schedule their own appointments via a unique link
  # sent through WhatsApp. This provides a simplified, mobile-first booking
  # experience without requiring login or technical knowledge.
  # 
  # FLOW:
  # 1. show       - Welcome screen with patient name confirmation
  # 2. select_week - Choose "this week" or "next weeks"
  # 3. select_day  - Choose specific day (Mon-Sat)
  # 4. select_period - Choose morning or afternoon
  # 5. confirm     - Review and confirm booking
  # 6. success     - Booking confirmed, show next steps
  # 
  # SECURITY:
  # - All actions are public (no authentication required)
  # - Access is controlled via unique self_booking_token
  # - Tokens are cryptographically secure (SecureRandom.urlsafe_base64)
  # 
  # ESSENTIAL: This controller is PUBLIC. All before_action filters from
  # ApplicationController are skipped to allow unauthenticated access.
  # ============================================================================
  class SelfBookingsController < ApplicationController
    # Skip ALL authentication and redirect filters
    skip_before_action :authenticate_user!
    skip_before_action :redirect_referral_users
    skip_before_action :redirect_doctor_users
    skip_before_action :set_referral
    skip_before_action :set_company_info
    
    # Ensure CSRF protection for form submissions
    protect_from_forgery with: :exception
    
    # Load lead for all actions except landing
    before_action :set_lead_by_token, except: [:landing]
    before_action :set_available_services
    
    # Layout specifically for public self-booking pages
    layout 'clinic_management/self_booking'

    # ============================================================================
    # GET /self_booking/:token
    # 
    # Welcome screen with personalized greeting.
    # Patient can confirm their name or indicate they are someone else.
    # ============================================================================
    def show
      @patient_name = @lead.patient_first_name
      @full_name = @lead.patient_full_name
    end

    # ============================================================================
    # POST /self_booking/:token/change_name
    # 
    # Handles when patient indicates they are not the expected person.
    # Shows a form to enter the correct name.
    # ============================================================================
    def change_name
      @patient_name = @lead.patient_first_name
    end

    # ============================================================================
    # POST /self_booking/:token/update_name
    # 
    # Processes patient identity change with phone number logic.
    # 
    # LOGIC:
    # - Same phone as original lead -> use original lead, save new name
    # - Different phone that exists -> switch to that phone's lead owner
    # - Different phone that's new -> create new lead with that phone
    # 
    # The actual lead to use is stored in session[:self_booking_lead_id]
    # The patient name is stored in session[:self_booking_patient_name]
    # ============================================================================
    def update_name
      patient_name = params[:patient_name]&.strip
      patient_phone = params[:patient_phone]&.gsub(/\D/, '') # Remove non-digits
      
      # Validate required fields
      if patient_name.blank?
        redirect_to self_booking_change_name_path(@lead.self_booking_token), 
                    alert: "Por favor, informe o nome do paciente."
        return
      end
      
      if patient_phone.blank?
        redirect_to self_booking_change_name_path(@lead.self_booking_token), 
                    alert: "Por favor, informe o telefone."
        return
      end
      
      # Determine which lead to use based on phone
      target_lead = determine_target_lead(patient_name, patient_phone)
      
      # Store booking context in session
      session[:self_booking_patient_name] = patient_name
      session[:self_booking_lead_id] = target_lead.id
      
      # Continue to week selection using the ORIGINAL token (for URL consistency)
      redirect_to self_booking_select_week_path(@lead.self_booking_token)
    end

    # ============================================================================
    # GET /self_booking/:token/select_week
    # 
    # Patient chooses between "this week" or "next weeks".
    # ============================================================================
    def select_week
      @patient_name = session[:self_booking_patient_name] || @lead.patient_first_name
      @this_week_services = services_this_week
      @next_week_services = services_next_weeks
      
      # If no services available at all, show message
      @has_services = @this_week_services.any? || @next_week_services.any?
    end

    # ============================================================================
    # GET /self_booking/:token/select_day
    # 
    # Patient chooses specific day of the week.
    # Shows available days based on week selection.
    # 
    # Params:
    # - week: 'this' or 'next'
    # ============================================================================
    def select_day
      @patient_name = session[:self_booking_patient_name] || @lead.patient_first_name
      @week = params[:week] || 'this'
      
      @available_days = if @week == 'this'
        services_this_week.group_by { |s| s.date.wday }
      else
        services_next_weeks.group_by { |s| s.date.wday }
      end
      
      @days_of_week = day_names_for_display(@available_days.keys)
    end

    # ============================================================================
    # GET /self_booking/:token/select_period
    # 
    # Patient chooses morning or afternoon.
    # 
    # Params:
    # - week: 'this' or 'next'
    # - day: day of week (0-6, where 0 is Sunday)
    # ============================================================================
    def select_period
      @patient_name = session[:self_booking_patient_name] || @lead.patient_first_name
      @week = params[:week]
      @day = params[:day].to_i
      
      # Find services for this day
      base_services = @week == 'this' ? services_this_week : services_next_weeks
      @day_services = base_services.select { |s| s.date.wday == @day }
      
      # Group by period (morning: before 12:00, afternoon: 12:00 and later)
      @morning_services = @day_services.select { |s| s.start_time.hour < 12 }
      @afternoon_services = @day_services.select { |s| s.start_time.hour >= 12 }
      
      @day_name = I18n.l(Date.today.beginning_of_week + (@day - 1).days, format: '%A')
    end

    # ============================================================================
    # GET /self_booking/:token/confirm
    # 
    # Shows booking confirmation screen with selected service details.
    # 
    # Params:
    # - service_id: the selected service ID
    # ============================================================================
    def confirm
      @patient_name = session[:self_booking_patient_name] || @lead.patient_first_name
      @service = Service.find_by(id: params[:service_id])
      
      unless @service
        redirect_to self_booking_path(@lead.self_booking_token), 
                    alert: "Serviço não encontrado. Por favor, selecione novamente."
        return
      end
      
      @formatted_date = I18n.l(@service.date, format: '%A, %d de %B')
      @formatted_time = "#{@service.start_time.strftime('%H:%M')} - #{@service.end_time.strftime('%H:%M')}"
    end

    # ============================================================================
    # POST /self_booking/:token/create_booking
    # 
    # Creates the actual booking (invitation + appointment).
    # This is the final step in the self-booking flow.
    # 
    # ESSENTIAL: Uses the target lead from session (may be different from URL token's lead)
    # when patient indicated they are someone else with a different phone.
    # 
    # Params:
    # - service_id: the selected service ID
    # ============================================================================
    def create_booking
      # Get the correct lead to use (may differ from @lead if patient changed identity)
      target_lead = get_target_lead_for_booking
      
      @patient_name = session[:self_booking_patient_name] || target_lead.patient_full_name
      @service = Service.find_by(id: params[:service_id])
      
      unless @service
        redirect_to self_booking_path(@lead.self_booking_token), 
                    alert: "Serviço não encontrado. Por favor, selecione novamente."
        return
      end
      
      # Check if already booked for this service (on the TARGET lead)
      existing_appointment = target_lead.appointments.joins(:service)
                                  .where(clinic_management_services: { id: @service.id })
                                  .where(status: 'agendado')
                                  .first
      
      if existing_appointment
        redirect_to self_booking_success_path(@lead.self_booking_token, already_booked: true)
        return
      end
      
      ActiveRecord::Base.transaction do
        # Find or create "Local" region for self-bookings
        region = Region.find_or_create_by!(name: 'Local')
        
        # Find "Auto-Marcação" referral or create one
        referral = Referral.find_or_create_by!(name: 'Auto-Marcação') do |r|
          r.code = 'AUTO'
        end
        
        # Create invitation linked to TARGET lead (the phone owner)
        @invitation = target_lead.invitations.create!(
          patient_name: @patient_name,
          region: region,
          referral: referral,
          date: Date.current
        )
        
        # Create appointment linked to TARGET lead
        @appointment = @invitation.appointments.create!(
          service: @service,
          lead: target_lead,
          status: 'agendado',
          referral_code: referral.code
        )
        
        # Update target lead's last appointment reference
        target_lead.update!(last_appointment_id: @appointment.id)
      end
      
      # Clear session data
      session.delete(:self_booking_patient_name)
      session.delete(:self_booking_lead_id)
      
      redirect_to self_booking_success_path(@lead.self_booking_token)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Self-booking failed: #{e.message}"
      redirect_to self_booking_path(@lead.self_booking_token), 
                  alert: "Não foi possível realizar o agendamento. Por favor, tente novamente."
    end

    # ============================================================================
    # GET /self_booking/:token/success
    # 
    # Shows booking confirmation with details.
    # Offers options to reschedule or add another booking.
    # 
    # ESSENTIAL: Uses target lead from session if patient changed identity
    # ============================================================================
    def success
      # Get the correct lead (may be different if patient changed identity)
      target_lead = get_target_lead_for_booking
      
      # Get patient name - prioritize invitation name, then session, then lead
      @appointment = target_lead.appointments.includes(:service, :invitation).order(created_at: :desc).first
      @patient_name = @appointment&.invitation&.patient_name&.split&.first || 
                      session[:self_booking_patient_name]&.split&.first || 
                      target_lead.patient_first_name
      
      @already_booked = params[:already_booked].present?
      
      if @appointment&.service
        @formatted_date = I18n.l(@appointment.service.date, format: '%A, %d de %B')
        @formatted_time = "#{@appointment.service.start_time.strftime('%H:%M')} - #{@appointment.service.end_time.strftime('%H:%M')}"
      end
      
      # Clear session data after showing success
      session.delete(:self_booking_patient_name)
      session.delete(:self_booking_lead_id)
    end

    private

    # ============================================================================
    # Loads the lead by self_booking_token from URL params.
    # Renders a 404-like page if token is invalid.
    # ============================================================================
    def set_lead_by_token
      @lead = Lead.find_by_self_booking_token(params[:token])
      
      unless @lead
        render :invalid_token, status: :not_found
        return
      end
    end

    # ============================================================================
    # Pre-loads available services (upcoming, not canceled)
    # ============================================================================
    def set_available_services
      @available_services = Service.upcoming.order(date: :asc)
    end

    # ============================================================================
    # Returns services available this week (from today until end of week)
    # ============================================================================
    def services_this_week
      end_of_week = Date.current.end_of_week
      @available_services.where(date: Date.current..end_of_week)
    end

    # ============================================================================
    # Returns services available in the next 2 weeks (after this week)
    # ============================================================================
    def services_next_weeks
      start_date = Date.current.end_of_week + 1.day
      end_date = start_date + 2.weeks
      @available_services.where(date: start_date..end_date)
    end

    # ============================================================================
    # Converts day numbers to displayable names
    # 
    # @param day_numbers [Array<Integer>] array of day numbers (0-6)
    # @return [Array<Hash>] array of {number:, name:} hashes
    # ============================================================================
    def day_names_for_display(day_numbers)
      day_names = {
        0 => 'Domingo',
        1 => 'Segunda-feira',
        2 => 'Terça-feira',
        3 => 'Quarta-feira',
        4 => 'Quinta-feira',
        5 => 'Sexta-feira',
        6 => 'Sábado'
      }
      
      day_numbers.sort.map do |num|
        { number: num, name: day_names[num] }
      end
    end

    # ============================================================================
    # LEAD RESOLUTION LOGIC
    # 
    # These methods handle the phone-based lead resolution when a patient
    # indicates they are not the expected person.
    # ============================================================================

    # ============================================================================
    # Determines which lead should own the appointment based on phone number.
    # 
    # LOGIC:
    # 1. Same phone as current lead -> use current lead
    # 2. Phone belongs to another lead -> use that lead (phone owner)
    # 3. Phone is new -> create new lead with that phone
    # 
    # @param patient_name [String] the patient's name
    # @param patient_phone [String] sanitized phone number (digits only)
    # @return [Lead] the lead to link the appointment to
    # ============================================================================
    def determine_target_lead(patient_name, patient_phone)
      original_phone = @lead.phone
      
      # Case 1: Same phone - use the original lead
      if patient_phone == original_phone
        Rails.logger.info "[SelfBooking] Same phone - using original lead ##{@lead.id}"
        return @lead
      end
      
      # Case 2: Check if phone belongs to another lead
      existing_lead = Lead.find_by(phone: patient_phone)
      
      if existing_lead.present?
        Rails.logger.info "[SelfBooking] Phone exists - using existing lead ##{existing_lead.id} (#{existing_lead.name})"
        return existing_lead
      end
      
      # Case 3: New phone - create new lead
      Rails.logger.info "[SelfBooking] New phone #{patient_phone} - creating new lead for #{patient_name}"
      
      new_lead = Lead.create!(
        name: patient_name,
        phone: patient_phone
      )
      
      # Generate self_booking_token for the new lead (for future use)
      new_lead.generate_self_booking_token!
      
      Rails.logger.info "[SelfBooking] Created new lead ##{new_lead.id} with phone #{patient_phone}"
      
      new_lead
    end

    # ============================================================================
    # Gets the target lead for booking from session or defaults to URL lead.
    # 
    # This allows the booking flow to use a different lead than the one
    # from the URL token when the patient changed their identity.
    # 
    # @return [Lead] the lead to create the appointment for
    # ============================================================================
    def get_target_lead_for_booking
      if session[:self_booking_lead_id].present?
        target = Lead.find_by(id: session[:self_booking_lead_id])
        return target if target.present?
      end
      
      # Default to the lead from URL token
      @lead
    end
  end
end
