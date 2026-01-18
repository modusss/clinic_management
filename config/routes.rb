ClinicManagement::Engine.routes.draw do
  root 'invitations#new'
  
  # ============================================================================
  # SELF-BOOKING ROUTES (PUBLIC - No authentication required)
  # 
  # These routes enable patients to self-schedule appointments via a unique link.
  # The link is generated for each lead and can be shared via WhatsApp.
  # 
  # FLOW:
  # 1.  GET  /self_booking/:token              -> show (welcome screen)
  # 2a. POST /self_booking/:token/select_patient -> select patient (if multiple)
  # 2b. GET  /self_booking/:token/change_name  -> change_name form (not in list)
  # 3.  POST /self_booking/:token/update_name  -> saves new name + phone
  # 4.  GET  /self_booking/:token/select_week  -> choose this/next week
  # 5.  GET  /self_booking/:token/select_day   -> choose day of week
  # 6.  GET  /self_booking/:token/select_period -> choose morning/afternoon
  # 7.  GET  /self_booking/:token/confirm      -> review booking
  # 8.  POST /self_booking/:token/create       -> create appointment
  # 9.  GET  /self_booking/:token/success      -> confirmation screen
  # ============================================================================
  scope 'self_booking/:token', as: 'self_booking' do
    get '/', to: 'self_bookings#show', as: ''
    post 'select_patient', to: 'self_bookings#select_patient'
    get 'change_name', to: 'self_bookings#change_name'
    post 'update_name', to: 'self_bookings#update_name'
    get 'select_week', to: 'self_bookings#select_week'
    get 'select_day', to: 'self_bookings#select_day'
    get 'select_period', to: 'self_bookings#select_period'
    get 'confirm', to: 'self_bookings#confirm'
    post 'create', to: 'self_bookings#create_booking', as: 'create'
    get 'success', to: 'self_bookings#success'
  end
  
  resources :invitations do
    member do
      get :edit_patient_name
      patch :update_patient_name
      get :cancel_edit_patient_name
    end
    collection do
      get 'new_patient_fitted/:service_id', action: "new_patient_fitted", as: "new_patient_fitted"
      post 'create_patient_fitted', action: "create_patient_fitted", as: "create_patient_fitted"
      post 'check_existing_phone', action: "check_existing_phone", as: "check_existing_phone"
    end
  end
  get '/performance_report', to: 'invitations#performance_report', as: 'performance_report'
  resources :lead_messages do
    collection do
      post :send_evolution_message
      post :refresh_preview
    end
  end

  # post search appointment service_id
  post 'search_appointment/:service_id', to: 'services#search_appointment', as: 'search_appointment'

  post 'search_index_today', to: 'prescriptions#search_index_today', as: 'search_index_today'

  resources :appointments do
    collection do
      get :my_reschedules
    end
    member do
      patch :update_comments
      patch :set_attendance
      patch :cancel_attendance
      post :reschedule
      post :search
      patch :toggle_confirmation
      patch :convert_to_organic
      patch :convert_to_active_effort
      get :edit_recapture_details
      patch :update_recapture_details
      get :view_recapture_details
    end
    resources :prescriptions do
      collection do
        get 'new_today', action: "new_today", as: "new_today"
        get 'edit_today', action: "edit_today", as: "edit_today"
      end
      member do 
        get 'show_today', action: "show_today", as: "show_today"
        get 'pdf', action: "pdf", as: "pdf"
        post 'send_whatsapp', action: "send_whatsapp", as: "send_whatsapp"
      end
    end
  end
  get 'prescriptions/index_today', to: "prescriptions#index_today", as: "index_today"
  post 'prescriptions/force_confirmation_today', to: "prescriptions#force_confirmation_today", as: "force_confirmation_today"
  get 'generate_order_pdf', to: 'prescriptions#generate_order_pdf', as: :generate_order_pdf
  get 'prescriptions/index_next', to: "prescriptions#index_next", as: "index_next"
  get 'prescriptions/index_before', to: "prescriptions#index_before", as: "index_before"

  resources :services do
    member do
      patch :cancel
    end
    collection do
      get 'index_by_referral/:referral_id', action: "index_by_referral", as: "index_by_referral"
    end
    collection do
      get 'show_by_referral/:referral_id', action: "show_by_referral", as: "show_by_referral"
    end
  end
  resources :time_slots
  resources :regions
  resources :service_types
  resources :leads do
    member do
      post :record_message_sent
      post :make_call
      post :verify_whatsapp
      patch :hide_from_absent
      patch :mark_no_whatsapp
      patch :mark_no_interest
      patch :mark_wrong_phone
      patch :restore_lead
      patch :toggle_whatsapp_status
    end
    collection do
      get 'absent'
      get 'attended'
      get 'cancelled'
      post 'search'
      post 'search_absents'
      get 'download_leads'
      get 'absent_download'
      get 'check_phone'
      post 'send_bulk_messages'
      post 'cancel_scheduled_message'
      get 'load_scheduled_messages'
      delete 'clear_all_scheduled_messages'
    end
  end
  post 'build_message/:lead_id', to: 'lead_messages#build_message', as: 'build_message'

  mount ActionCable.server => '/cable'
end


