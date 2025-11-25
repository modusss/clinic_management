ClinicManagement::Engine.routes.draw do
  root 'invitations#new'
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
    end
  end
  post 'build_message/:lead_id', to: 'lead_messages#build_message', as: 'build_message'

  mount ActionCable.server => '/cable'
end


