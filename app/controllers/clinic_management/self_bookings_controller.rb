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
    # Updates the patient name for the booking.
    # Stores in session to use when creating the invitation.
    # ============================================================================
    def update_name
      session[:self_booking_patient_name] = params[:patient_name]
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
    # Params:
    # - service_id: the selected service ID
    # ============================================================================
    def create_booking
      @patient_name = session[:self_booking_patient_name] || @lead.patient_full_name
      @service = Service.find_by(id: params[:service_id])
      
      unless @service
        redirect_to self_booking_path(@lead.self_booking_token), 
                    alert: "Serviço não encontrado. Por favor, selecione novamente."
        return
      end
      
      # Check if already booked for this service
      existing_appointment = @lead.appointments.joins(:service)
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
        
        # Create invitation
        @invitation = @lead.invitations.create!(
          patient_name: @patient_name,
          region: region,
          referral: referral,
          date: Date.current
        )
        
        # Create appointment
        @appointment = @invitation.appointments.create!(
          service: @service,
          lead: @lead,
          status: 'agendado',
          referral_code: referral.code
        )
        
        # Update lead's last appointment reference
        @lead.update!(last_appointment_id: @appointment.id)
      end
      
      # Clear session data
      session.delete(:self_booking_patient_name)
      
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
    # ============================================================================
    def success
      @patient_name = @lead.patient_first_name
      @already_booked = params[:already_booked].present?
      
      # Get the most recent appointment
      @appointment = @lead.appointments.includes(:service).order(created_at: :desc).first
      
      if @appointment&.service
        @formatted_date = I18n.l(@appointment.service.date, format: '%A, %d de %B')
        @formatted_time = "#{@appointment.service.start_time.strftime('%H:%M')} - #{@appointment.service.end_time.strftime('%H:%M')}"
      end
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
  end
end
