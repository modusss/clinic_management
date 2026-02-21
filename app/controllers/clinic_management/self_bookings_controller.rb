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
    
    # Load lead for all actions except public routes
    before_action :set_lead_by_token, except: [:landing, :public_registration, :create_public_registration]
    before_action :set_available_services
    # ESSENTIAL: Block entire flow when account has self_booking_enabled disabled (Adicionais toggle)
    before_action :ensure_self_booking_enabled_for_context

    # Layout specifically for public self-booking pages
    layout 'clinic_management/self_booking'

    # ============================================================================
    # GET /public_booking
    # 
    # Public registration page that doesn't require a lead token.
    # Used by staff/referrals to share a generic booking link.
    # 
    # Params:
    # - ref: referral_id (for commission attribution)
    # - reg_by: user_id (who shared the link - effort tracking)
    # ============================================================================
    def public_registration
      # Capture referral attribution from URL
      if params[:ref].present?
        session[:self_booking_referral_id] = params[:ref].to_i
        Rails.logger.info "[SelfBooking] Public registration - Referral ID #{params[:ref]} captured"
      end
      
      # Capture who shared the link
      if params[:reg_by].present?
        session[:self_booking_registered_by_user_id] = params[:reg_by].to_i
        Rails.logger.info "[SelfBooking] Public registration - Registered by User ID #{params[:reg_by]} captured"
      end
      
      # Get referral name for display (if present)
      @referral = Referral.find_by(id: params[:ref]) if params[:ref].present?
      @sharer = User.find_by(id: params[:reg_by]) if params[:reg_by].present?
    end

    # ============================================================================
    # POST /public_booking/register
    # 
    # Creates a new Lead from public registration form.
    # 
    # LOGIC:
    # 1. If phone exists -> use existing lead
    # 2. If phone is new -> create new lead
    # Then redirect to the booking flow with proper attribution.
    # 
    # MINOR PATIENT LOGIC:
    # When is_minor=1, the form includes guardian_name field:
    # - guardian_name -> Lead.name (phone owner/responsible for WhatsApp messages)
    # - patient_name -> Invitation.patient_name (the actual patient being treated)
    # 
    # This allows proper tracking: the Lead represents the phone owner (guardian),
    # while the Invitation/Appointment tracks the actual patient (minor).
    # ============================================================================
    def create_public_registration
      patient_name = params[:patient_name]&.strip
      patient_phone = params[:patient_phone]&.gsub(/\D/, '')
      is_minor = params[:is_minor] == "1"
      guardian_name = params[:guardian_name]&.strip
      
      # Validate patient name
      if patient_name.blank?
        redirect_to public_booking_path(ref: params[:ref], reg_by: params[:reg_by]),
                    alert: "Por favor, informe o nome do paciente."
        return
      end
      
      # Validate phone
      if patient_phone.blank? || patient_phone.length < 10
        redirect_to public_booking_path(ref: params[:ref], reg_by: params[:reg_by]),
                    alert: "Por favor, informe um telefone válido."
        return
      end
      
      # ESSENTIAL: Validate guardian name when patient is a minor
      if is_minor && guardian_name.blank?
        redirect_to public_booking_path(ref: params[:ref], reg_by: params[:reg_by]),
                    alert: "Por favor, informe o nome do responsável pelo menor."
        return
      end
      
      # Determine the lead name based on minor status
      # - If minor: Lead.name = guardian (phone owner who receives messages)
      # - If adult: Lead.name = patient (same person)
      lead_name = is_minor ? guardian_name : patient_name
      
      # Find or create lead
      target_lead = Lead.find_by(phone: patient_phone)
      
      if target_lead.nil?
        target_lead = Lead.create!(
          name: lead_name,
          phone: patient_phone
        )
        target_lead.generate_self_booking_token!
        Rails.logger.info "[SelfBooking] Public registration - Created new lead ##{target_lead.id} (#{is_minor ? 'minor patient, guardian: ' + lead_name : 'adult patient'})"
      else
        # Update lead name if it's a new guardian for an existing phone
        if is_minor && target_lead.name != lead_name
          Rails.logger.info "[SelfBooking] Public registration - Updating lead ##{target_lead.id} name to guardian: #{lead_name}"
          target_lead.update!(name: lead_name)
        end
        Rails.logger.info "[SelfBooking] Public registration - Using existing lead ##{target_lead.id}"
      end
      
      # Store in session
      session[:self_booking_lead_id] = target_lead.id
      session[:self_booking_is_minor] = is_minor
      
      # Preserve referral/reg_by from URL params if present
      session[:self_booking_referral_id] = params[:ref].to_i if params[:ref].present?
      session[:self_booking_registered_by_user_id] = params[:reg_by].to_i if params[:reg_by].present?
      
      # ESSENTIAL: Store the minor patient name temporarily so it can be added to distinct_patients
      # This ensures both guardian and minor appear in the patient selection screen
      if is_minor
        session[:self_booking_pending_minor_name] = patient_name
        session.delete(:self_booking_patient_names)
        Rails.logger.info "[SelfBooking] Public registration - Minor patient '#{patient_name}' stored, redirecting to patient selection"
        # Redirect to show page where user can select between guardian and minor
        redirect_to self_booking_path(target_lead.self_booking_token!)
      else
        # For adults, store patient_name and go directly to week selection
        session[:self_booking_patient_name] = patient_name
        session[:self_booking_patient_names] = [patient_name]
        redirect_to self_booking_select_week_path(target_lead.self_booking_token!)
      end
    end

    # ============================================================================
    # GET /self_booking/:token
    # 
    # Welcome screen with personalized greeting.
    # 
    # IMPORTANT: The greeting shows the Lead owner's name (phone owner), not the
    # last patient name. A Lead (phone) can have multiple patients associated
    # (e.g., Rafael the father is the phone owner, Joana the daughter is a patient).
    # 
    # If multiple distinct patients exist, show a select dropdown for the user
    # to choose which patient they are.
    # 
    # REFERRAL ATTRIBUTION:
    # Captures the 'ref' parameter (referral_id) if present in the URL.
    # This is used later to attribute the booking to the correct referral.
    # ============================================================================
    def show
      # Show the Lead owner's name (phone owner) in the greeting
      @lead_name = @lead.owner_first_name
      
      # Get distinct patients associated with this phone number
      @distinct_patients = @lead.distinct_patients
      
      # ESSENTIAL: If there's a pending minor name from public_registration,
      # add it to the patient list so the guardian can choose between themselves and the minor
      if session[:self_booking_pending_minor_name].present?
        pending_minor_name = session[:self_booking_pending_minor_name]
        first_name = pending_minor_name.split.first&.strip&.capitalize
        
        # Check if this minor is not already in the list (by first name)
        minor_key = @lead.normalize_name_for_comparison(first_name)
        already_exists = @distinct_patients.any? do |p|
          @lead.normalize_name_for_comparison(p[:first_name]) == minor_key
        end
        
        unless already_exists
          @distinct_patients << {
            first_name: first_name,
            full_name: pending_minor_name.strip
          }
          # Sort by first name
          @distinct_patients.sort_by! { |p| p[:first_name].downcase }
          Rails.logger.info "[SelfBooking] Added pending minor '#{pending_minor_name}' to patient selection"
        end
      end
      
      @has_multiple_patients = @distinct_patients.count > 1
      
      # Capture referral attribution from URL (if link was shared by a referral)
      # Store in session so it persists through the booking flow
      if params[:ref].present?
        session[:self_booking_referral_id] = params[:ref].to_i
        Rails.logger.info "[SelfBooking] Referral ID #{params[:ref]} captured from URL"
      end
      
      # ESSENTIAL: Capture who shared/sent the link (reg_by parameter)
      # This tracks the USER who sent the link, separate from referral commission attribution.
      # Example: Assistant Jussara sends a link -> reg_by=jussara_user_id
      #          But commission goes to the referral within 180-day grace period
      if params[:reg_by].present?
        session[:self_booking_registered_by_user_id] = params[:reg_by].to_i
        Rails.logger.info "[SelfBooking] Registered by User ID #{params[:reg_by]} captured from URL"
      end
    end

    # ============================================================================
    # POST /self_booking/:token/select_patient
    # 
    # Handles patient selection when multiple patients are associated with
    # the same phone number (Lead). Stores the selected patient name in session.
    # 
    # Params:
    # - selected_patient: the full name of the selected patient
    # ============================================================================
    def select_patient
      selected_patients = Array(params[:selected_patients]).map { |name| name.to_s.strip }.reject(&:blank?).uniq
      selected_patient = params[:selected_patient]&.strip
      selected_patients = [selected_patient] if selected_patients.blank? && selected_patient.present?

      if selected_patients.blank?
        redirect_to self_booking_path(@lead.self_booking_token), 
                    alert: "Por favor, selecione um paciente."
        return
      end
      
      # Store selected patients in session.
      # ESSENTIAL: Keep the first name in self_booking_patient_name for backward compatibility.
      session[:self_booking_patient_names] = selected_patients
      session[:self_booking_patient_name] = selected_patients.first
      session[:self_booking_lead_id] = @lead.id
      
      # Clear the pending minor name since a patient was selected
      session.delete(:self_booking_pending_minor_name)
      
      Rails.logger.info "[SelfBooking] Patients selected: #{selected_patients.join(', ')} for lead ##{@lead.id}"
      
      # Continue to week selection
      redirect_to self_booking_select_week_path(@lead.self_booking_token)
    end

    # ============================================================================
    # GET /self_booking/:token/change_name
    # 
    # Handles when patient indicates they are not the expected person
    # (or not in the list of patients). Shows a form to enter the correct name.
    # ============================================================================
    def change_name
      @patient_name = @lead.owner_first_name
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
      session[:self_booking_patient_names] = [patient_name]
      session[:self_booking_lead_id] = target_lead.id
      
      # Continue to week selection using the ORIGINAL token (for URL consistency)
      redirect_to self_booking_select_week_path(@lead.self_booking_token)
    end

    # ============================================================================
    # GET /self_booking/:token/new_registration
    # 
    # Handles users who received a booking link via WhatsApp from another patient.
    # 
    # TWO SCENARIOS:
    # 1. Phone ALREADY EXISTS in system (belongs to another Lead):
    #    -> Redirect directly to that Lead's booking flow (no registration needed)
    #    -> Store patient name in session for personalization
    # 
    # 2. Phone is NEW (doesn't exist in system):
    #    -> Show registration form to create new Lead
    #    -> Phone is FIXED (verified via WhatsApp)
    # 
    # REFERRAL ATTRIBUTION: Always "Local" since this is organic/shared by patient
    # 
    # Params:
    # - phone: the user's phone number (required)
    # - name: optional pre-filled name (from the share form)
    # ============================================================================
    def new_registration
      @new_phone = params[:phone]&.gsub(/\D/, '')
      @suggested_name = params[:name]
      
      if @new_phone.blank? || @new_phone.length < 10
        redirect_to self_booking_path(@lead.self_booking_token), 
                    alert: "Link inválido. Por favor, solicite um novo link."
        return
      end
      
      # Check if a lead with this phone already exists
      existing_lead = Lead.find_by(phone: @new_phone)
      
      if existing_lead.present?
        # CASE 1: Phone already exists - redirect to that Lead's booking flow
        Rails.logger.info "[SelfBooking] Phone #{@new_phone} already exists - redirecting to lead ##{existing_lead.id}"
        
        # Store patient name if provided (for personalization)
        if @suggested_name.present?
          session[:self_booking_patient_name] = @suggested_name
          session[:self_booking_patient_names] = [@suggested_name]
        end
        session[:self_booking_lead_id] = existing_lead.id
        
        # Force Local attribution since this was patient-shared
        session[:self_booking_force_local] = true
        
        # Redirect to the existing Lead's booking page
        redirect_to self_booking_select_week_path(existing_lead.self_booking_token!)
        return
      end
      
      # CASE 2: New phone - show registration form
      @formatted_phone = @new_phone.gsub(/(\d{2})(\d{5})(\d{4})/, '(\1) \2-\3')
    end

    # ============================================================================
    # POST /self_booking/:token/create_registration
    # 
    # Creates a new Lead for the user who received the link via WhatsApp.
    # 
    # LOGIC:
    # 1. If phone already exists -> use existing lead, store patient name
    # 2. If phone is new -> create new Lead with provided name and phone
    # 
    # REFERRAL ATTRIBUTION: Always "Local" (organic/shared by patient)
    # 
    # Params:
    # - patient_name: the new user's name (required)
    # - patient_phone: the phone number (from hidden field)
    # ============================================================================
    def create_registration
      patient_name = params[:patient_name]&.strip
      patient_phone = params[:patient_phone]&.gsub(/\D/, '')
      
      if patient_name.blank?
        redirect_to self_booking_new_registration_path(@lead.self_booking_token, phone: patient_phone),
                    alert: "Por favor, informe seu nome."
        return
      end
      
      if patient_phone.blank? || patient_phone.length < 10
        redirect_to self_booking_path(@lead.self_booking_token),
                    alert: "Telefone inválido. Por favor, solicite um novo link."
        return
      end
      
      # Find or create lead for this phone
      target_lead = Lead.find_by(phone: patient_phone)
      
      if target_lead.nil?
        # Create new lead with the provided information
        target_lead = Lead.create!(
          name: patient_name,
          phone: patient_phone
        )
        target_lead.generate_self_booking_token!
        Rails.logger.info "[SelfBooking] Created new lead ##{target_lead.id} via new_registration"
      else
        Rails.logger.info "[SelfBooking] Using existing lead ##{target_lead.id} for phone #{patient_phone}"
      end
      
      # Store in session
      session[:self_booking_patient_name] = patient_name
      session[:self_booking_patient_names] = [patient_name]
      session[:self_booking_lead_id] = target_lead.id
      
      # IMPORTANT: Clear any referral attribution - this is always "Local"
      # because it was shared by a patient, not by a referral
      session[:self_booking_referral_id] = nil
      session[:self_booking_force_local] = true
      
      # Redirect to week selection using the NEW lead's token
      redirect_to self_booking_select_week_path(target_lead.self_booking_token!)
    end

    # ============================================================================
    # GET /self_booking/:token/share_invite
    # 
    # Shows a registration form for friends who received a shared link.
    # This is the entry point when a patient shares the booking link with friends.
    # 
    # The user must provide their name and phone number to create their profile.
    # 
    # REFERRAL ATTRIBUTION: Always "Local" (patient shared, not referral)
    # ============================================================================
    def share_invite
      @sharer_name = @lead.owner_first_name
    end

    # ============================================================================
    # POST /self_booking/:token/create_shared_booking
    # 
    # Creates a new Lead for someone who received a shared link from a patient.
    # 
    # LOGIC:
    # 1. If phone already exists -> redirect to that Lead's booking flow
    # 2. If phone is new -> create new Lead and continue booking
    # 
    # REFERRAL ATTRIBUTION: Always "Local" (patient shared, not referral)
    # ============================================================================
    def create_shared_booking
      patient_name = params[:patient_name]&.strip
      patient_phone = params[:patient_phone]&.gsub(/\D/, '')
      
      if patient_name.blank?
        redirect_to self_booking_share_invite_path(@lead.self_booking_token),
                    alert: "Por favor, informe seu nome."
        return
      end
      
      if patient_phone.blank? || patient_phone.length < 10
        redirect_to self_booking_share_invite_path(@lead.self_booking_token),
                    alert: "Por favor, informe um telefone válido."
        return
      end
      
      # Check if phone already exists
      existing_lead = Lead.find_by(phone: patient_phone)
      
      if existing_lead.present?
        # Phone exists - redirect to that Lead's booking flow
        Rails.logger.info "[SelfBooking] Shared invite: phone #{patient_phone} exists - using lead ##{existing_lead.id}"
        
        session[:self_booking_patient_name] = patient_name
        session[:self_booking_patient_names] = [patient_name]
        session[:self_booking_lead_id] = existing_lead.id
        session[:self_booking_force_local] = true
        
        redirect_to self_booking_select_week_path(existing_lead.self_booking_token!)
        return
      end
      
      # Create new lead
      new_lead = Lead.create!(
        name: patient_name,
        phone: patient_phone
      )
      new_lead.generate_self_booking_token!
      
      Rails.logger.info "[SelfBooking] Shared invite: created new lead ##{new_lead.id} for #{patient_name}"
      
      # Store in session
      session[:self_booking_patient_name] = patient_name
      session[:self_booking_patient_names] = [patient_name]
      session[:self_booking_lead_id] = new_lead.id
      session[:self_booking_force_local] = true
      
      # Redirect to booking flow
      redirect_to self_booking_select_week_path(new_lead.self_booking_token!)
    end

    # ============================================================================
    # GET /self_booking/:token/select_week
    # 
    # Patient chooses between "this week" or "next weeks".
    # 
    # IMPORTANT: If the patient already has a future appointment scheduled,
    # it will be displayed here so they don't get confused and can choose
    # to keep it or reschedule.
    # ============================================================================
    def select_week
      @selected_patient_names = selected_patient_names_for_booking
      @patient_name = @selected_patient_names.first || @lead.patient_first_name
      @full_patient_name = @selected_patient_names.first || @lead.patient_full_name
      @this_week_services = services_this_week
      @next_week_services = services_next_weeks
      
      # If no services available at all, show message
      @has_services = @this_week_services.any? || @next_week_services.any?
      
      # Check existing future appointments for selected patients.
      # ESSENTIAL: For multi-select flows we show each patient's current appointment.
      target_lead = get_target_lead_for_booking
      @existing_appointments = find_existing_future_appointments(target_lead, @selected_patient_names)
      @existing_appointment = @existing_appointments.first
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
      @selected_patient_names = selected_patient_names_for_booking
      @patient_name = @selected_patient_names.first || session[:self_booking_patient_name] || @lead.patient_first_name
      @is_multi_patient_booking = @selected_patient_names.size > 1
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
      
      selected_patient_names = selected_patient_names_for_booking
      selected_patient_names = [session[:self_booking_patient_name]].compact if selected_patient_names.blank?
      @patient_name = selected_patient_names.first || target_lead.patient_full_name
      @service = Service.find_by(id: params[:service_id])
      
      unless @service
        redirect_to self_booking_path(@lead.self_booking_token), 
                    alert: "Serviço não encontrado. Por favor, selecione novamente."
        return
      end
      
      ActiveRecord::Base.transaction do
        # Find or create "Local" region for self-bookings
        region = Region.find_or_create_by!(name: 'Local')
        
        # Determine referral attribution based on who shared the link
        referral = determine_referral_attribution(target_lead)
        
        Rails.logger.info "[SelfBooking] Referral attribution: #{referral.name} (ID: #{referral.id})"
        
        # ESSENTIAL: Get the user who shared/sent the link (if captured from URL)
        # This is separate from referral commission - tracks who did the work of sharing
        registered_by_user_id = session[:self_booking_registered_by_user_id]
        if registered_by_user_id.present?
          registered_user = User.find_by(id: registered_by_user_id)
          Rails.logger.info "[SelfBooking] Registered by: #{registered_user&.name} (User ID: #{registered_by_user_id})"
        end
        
        created_appointments = []
        skipped_patient_names = []

        selected_patient_names.each do |patient_name|
          if appointment_exists_for_patient_and_service?(target_lead, patient_name, @service.id)
            skipped_patient_names << patient_name
            next
          end

          # ESSENTIAL: When patient is being rescheduled via self-booking link,
          # previous active appointments must be marked as 'remarcado'.
          mark_previous_appointments_as_rescheduled!(target_lead, patient_name, @service.id)

          # Create invitation linked to TARGET lead (the phone owner)
          invitation = target_lead.invitations.create!(
            patient_name: patient_name,
            region: region,
            referral: referral,
            date: Date.current
          )

          # Create appointment linked to TARGET lead
          # ESSENTIAL: Include tracking fields:
          # - registered_by_user_id: who shared the link (effort tracking)
          # - self_booked: true to indicate this came from self-booking flow (channel tracking)
          appointment = invitation.appointments.create!(
            service: @service,
            lead: target_lead,
            status: 'agendado',
            referral_code: referral.code,
            registered_by_user_id: registered_by_user_id,
            self_booked: true # ESSENTIAL: Marks this appointment as created via self-booking
          )
          created_appointments << appointment
        end

        if created_appointments.blank?
          session[:self_booking_last_created_patient_names] = []
          session[:self_booking_last_skipped_patient_names] = skipped_patient_names
          raise ActiveRecord::Rollback
        end

        @appointment = created_appointments.last
        @created_patient_names = created_appointments.map { |apt| apt.invitation.patient_name }
        @skipped_patient_names = skipped_patient_names

        # Update target lead's last appointment reference
        target_lead.update!(last_appointment_id: @appointment.id)
      end

      if @appointment.nil?
        redirect_to self_booking_success_path(@lead.self_booking_token, already_booked: true)
        return
      end

      session[:self_booking_last_created_patient_names] = @created_patient_names
      session[:self_booking_last_skipped_patient_names] = @skipped_patient_names
      
      # Clear session data
      session.delete(:self_booking_patient_name)
      session.delete(:self_booking_patient_names)
      session.delete(:self_booking_lead_id)
      session.delete(:self_booking_referral_id)
      session.delete(:self_booking_registered_by_user_id)
      session.delete(:self_booking_is_minor)
      session.delete(:self_booking_pending_minor_name)
      
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
      @created_patient_names = Array(session[:self_booking_last_created_patient_names]).reject(&:blank?)
      @skipped_patient_names = Array(session[:self_booking_last_skipped_patient_names]).reject(&:blank?)
      @is_multi_patient_result = @created_patient_names.size > 1
      
      if @appointment&.service
        @formatted_date = I18n.l(@appointment.service.date, format: '%A, %d de %B')
        @formatted_time = "#{@appointment.service.start_time.strftime('%H:%M')} - #{@appointment.service.end_time.strftime('%H:%M')}"
      end
      
      # Clear session data after showing success
      session.delete(:self_booking_patient_name)
      session.delete(:self_booking_patient_names)
      session.delete(:self_booking_lead_id)
      session.delete(:self_booking_referral_id)
      session.delete(:self_booking_registered_by_user_id)
      session.delete(:self_booking_is_minor)
      session.delete(:self_booking_pending_minor_name)
      session.delete(:self_booking_last_created_patient_names)
      session.delete(:self_booking_last_skipped_patient_names)
    end

    private

    # ============================================================================
    # SELF-BOOKING FEATURE FLAG (account.self_booking_enabled)
    #
    # Blocks all actions when the context account has self_booking_enabled false.
    # Context account is resolved from: @lead.account (when lead has account_id),
    # session[:self_booking_registered_by_user_id] (user who shared link), or
    # params[:reg_by] (for public_registration). When account cannot be determined,
    # access is allowed (backward compat for links without reg_by).
    # ============================================================================
    def ensure_self_booking_enabled_for_context
      account = self_booking_context_account
      return if account.nil?
      return if account.self_booking_enabled?

      Rails.logger.info "[SelfBooking] Blocked: account ##{account.id} has self_booking_enabled false"
      render :feature_disabled, status: :forbidden
    end

    # Returns the Account to check for self_booking_enabled in this request.
    # Used when there is no current_user (public controller).
    #
    # @return [Account, nil]
    def self_booking_context_account
      # 1. From lead (when lead has account_id - future-proof)
      if defined?(@lead) && @lead.present? && @lead.respond_to?(:account) && @lead.account.present?
        return @lead.account
      end

      # 2. From session (user who shared the link, set when opening link with reg_by)
      user_id = session[:self_booking_registered_by_user_id]
      if user_id.present?
        user = User.find_by(id: user_id)
        return user&.accounts&.first
      end

      # 3. From params (public_registration / create_public_registration)
      reg_by = params[:reg_by]
      if reg_by.present?
        user = User.find_by(id: reg_by)
        return user&.accounts&.first
      end

      nil
    end

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
    # EXISTING APPOINTMENT CHECK
    # 
    # Finds any future appointment for the patient to display on the booking screen.
    # This prevents confusion and allows the patient to see their existing booking
    # or choose to reschedule.
    # ============================================================================

    # ============================================================================
    # Finds an existing future appointment for the given patient.
    # 
    # Searches by:
    # 1. Appointments linked to the lead with status 'agendado'
    # 2. Service date >= today
    # 3. Optionally matches patient_name (for leads with multiple patients)
    # 
    # @param lead [Lead] the lead to search appointments for
    # @param patient_name [String] optional patient name to filter by
    # @return [Appointment, nil] the existing future appointment, if any
    # ============================================================================
    def find_existing_future_appointment(lead, patient_name = nil)
      appointments = lead.appointments
                         .includes(:service, invitation: :referral)
                         .joins(:service)
                         .where(status: 'agendado')
                         .where('clinic_management_services.date >= ?', Date.current)
                         .order('clinic_management_services.date ASC')
      
      # If patient_name is provided, try to find appointment with matching name
      if patient_name.present?
        # Normalize patient name for comparison
        normalized_name = patient_name.downcase.strip
        first_name = normalized_name.split.first
        
        # First try exact match on invitation patient_name
        matching_appointment = appointments.find do |apt|
          apt_name = apt.invitation&.patient_name&.downcase&.strip
          next false unless apt_name
          
          # Match if same first name
          apt_first_name = apt_name.split.first
          apt_first_name == first_name
        end
        
        return matching_appointment if matching_appointment
      end
      
      # Return the earliest future appointment if no specific match
      appointments.first
    end

    # ============================================================================
    # Finds existing future appointments for one or many selected patients.
    #
    # @param lead [Lead] the lead to search appointments for
    # @param patient_names [Array<String>] selected patient names
    # @return [Array<Appointment>] earliest future appointment for each patient
    # ============================================================================
    def find_existing_future_appointments(lead, patient_names)
      names = Array(patient_names).map(&:to_s).map(&:strip).reject(&:blank?).uniq
      return [find_existing_future_appointment(lead)].compact if names.blank?

      names.map { |name| find_existing_future_appointment(lead, name) }.compact
    end

    # ============================================================================
    # Checks if the selected patient already has an active booking in the service.
    # Uses first-name matching to keep behavior aligned with existing flow.
    #
    # @param lead [Lead] the target lead
    # @param patient_name [String] patient full name
    # @param service_id [Integer] selected service id
    # @return [Boolean]
    # ============================================================================
    def appointment_exists_for_patient_and_service?(lead, patient_name, service_id)
      normalized_first_name = normalized_patient_first_name(patient_name)
      return false if normalized_first_name.blank?

      lead.appointments
          .joins(:service, :invitation)
          .where(clinic_management_services: { id: service_id })
          .where(status: 'agendado')
          .any? do |appointment|
            normalized_patient_first_name(appointment.invitation&.patient_name) == normalized_first_name
          end
    end

    # Marks previous active bookings as rescheduled when patient picks a new date.
    #
    # Rules:
    # - same patient (first-name match for consistency with existing flow)
    # - same lead (same phone owner context)
    # - status currently 'agendado'
    # - different service from the newly selected one
    # - service date from today onward (future/current schedule)
    #
    # @param lead [Lead] target lead
    # @param patient_name [String] patient full name
    # @param new_service_id [Integer] selected new service id
    # @return [Integer] number of updated appointments
    def mark_previous_appointments_as_rescheduled!(lead, patient_name, new_service_id)
      normalized_first_name = normalized_patient_first_name(patient_name)
      return 0 if normalized_first_name.blank?

      appointments_to_reschedule = lead.appointments
                                     .joins(:service, :invitation)
                                     .where(status: 'agendado')
                                     .where('clinic_management_services.date >= ?', Date.current)
                                     .where.not(clinic_management_services: { id: new_service_id })
                                     .select do |appointment|
        normalized_patient_first_name(appointment.invitation&.patient_name) == normalized_first_name
      end

      updated_count = 0
      appointments_to_reschedule.each do |appointment|
        # ESSENTIAL: Status transition to "remarcado" must bypass create-time validations
        # that can block historical schedule updates for the same patient/service.
        appointment.update_columns(status: 'remarcado', updated_at: Time.current)
        updated_count += 1
      end

      if updated_count.positive?
        Rails.logger.info "[SelfBooking] Marked #{updated_count} previous appointment(s) as remarcado for patient #{patient_name}"
      end

      updated_count
    end

    # Returns normalized patient first name for safe comparison.
    #
    # @param full_name [String]
    # @return [String]
    def normalized_patient_first_name(full_name)
      full_name.to_s.downcase.strip.split.first.to_s
    end

    # Returns selected patient names from session, with backward compatibility.
    #
    # @return [Array<String>]
    def selected_patient_names_for_booking
      names = Array(session[:self_booking_patient_names]).map { |name| name.to_s.strip }.reject(&:blank?).uniq
      names = [session[:self_booking_patient_name].to_s.strip] if names.blank? && session[:self_booking_patient_name].present?
      names
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

    # ============================================================================
    # REFERRAL ATTRIBUTION LOGIC
    # 
    # Determines which referral should be credited for this self-booking.
    # 
    # RULES:
    # 0. If force_local flag is set (patient shared with someone else):
    #    -> Always "Local" (no referral effort involved)
    # 
    # 1. If link was shared by a referral (ref param in URL):
    #    -> Attribute to that referral (their effort brought the patient)
    # 
    # 2. If link was shared by clinic staff (no ref param):
    #    -> Check the patient's last appointment date:
    #    2.1 Last appointment <= 180 days ago (within grace period):
    #        -> Attribute to the ORIGINAL referral from last appointment
    #        (referral still gets credit during the 180-day grace period)
    #    2.2 Last appointment > 180 days ago (grace period expired):
    #        -> Attribute to "Local" (organic recapture by clinic)
    #        (clinic's own effort to bring patient back)
    # 
    # ESSENTIAL: The 180-day grace period protects referral attribution.
    # Within 180 days, the original referral still "owns" the patient.
    # After 180 days, the patient is considered organic/local.
    # 
    # @param target_lead [Lead] the lead being booked
    # @return [Referral] the referral to attribute the booking to
    # ============================================================================
    def determine_referral_attribution(target_lead)
      # CASE 0: Force Local - when a patient shared the link with someone else
      # (new registration flow via WhatsApp to different phone)
      if session[:self_booking_force_local].present?
        Rails.logger.info "[SelfBooking] Attribution: Local (force_local flag - patient shared link)"
        session.delete(:self_booking_force_local) # Clear the flag
        return find_or_create_local_referral
      end
      
      # CASE 1: Link was shared by a referral (captured in session from URL param)
      if session[:self_booking_referral_id].present?
        referral = Referral.find_by(id: session[:self_booking_referral_id])
        if referral.present?
          Rails.logger.info "[SelfBooking] Attribution: Referral #{referral.name} (shared the link)"
          return referral
        end
      end
      
      # CASE 2: Link was shared by clinic staff (no ref param)
      # Apply the 180-day rule based on last appointment
      last_appointment = target_lead.appointments
                                    .includes(invitation: :referral)
                                    .joins(:service)
                                    .order('clinic_management_services.date DESC')
                                    .first
      
      if last_appointment.present? && last_appointment.service.present?
        days_since_last = (Date.current - last_appointment.service.date).to_i
        original_referral = last_appointment.invitation&.referral
        
        Rails.logger.info "[SelfBooking] Last appointment was #{days_since_last} days ago"
        
        # CASE 2.1: Within 180-day grace period - attribute to original referral
        # The referral still "owns" this patient during the grace period
        if days_since_last <= 180 && original_referral.present?
          Rails.logger.info "[SelfBooking] Attribution: Original referral #{original_referral.name} (within 180-day grace period)"
          return original_referral
        end
        
        # CASE 2.2: Grace period expired (> 180 days) - attribute to "Local"
        Rails.logger.info "[SelfBooking] Attribution: Local (grace period expired, >180 days)"
      else
        Rails.logger.info "[SelfBooking] Attribution: Local (no previous appointment)"
      end
      
      # Default to "Local" for organic/clinic recapture
      find_or_create_local_referral
    end

    # ============================================================================
    # Helper method to find or create the "Local" referral
    # Used for organic/patient-shared bookings
    # 
    # @return [Referral] the "Local" referral
    # ============================================================================
    def find_or_create_local_referral
      Referral.find_or_create_by!(name: 'Local') do |r|
        r.code = 'LOCAL'
      end
    end
  end
end
