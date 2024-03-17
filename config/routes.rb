ClinicManagement::Engine.routes.draw do
  root 'invitations#new'
  resources :invitations do
    collection do
      get 'new_patient_fitted/:service_id', action: "new_patient_fitted", as: "new_patient_fitted"
      post 'create_patient_fitted', action: "create_patient_fitted", as: "create_patient_fitted"
    end
  end
  resources :lead_messages

  # post search appointment service_id
  post 'search_appointment/:service_id', to: 'services#search_appointment', as: 'search_appointment'

  resources :appointments do
    member do
      patch :set_attendance
      patch :cancel_attendance
      post :reschedule
      post :search
    end
    resources :prescriptions do
      collection do
        get 'new_today', action: "new_today", as: "new_today"
        get 'edit_today', action: "edit_today", as: "edit_today"
      end
      member do 
        get 'show_today', action: "show_today", as: "show_today"
        get 'pdf', action: "pdf", as: "pdf"
      end
    end
  end
  get 'prescriptions/index_today', to: "prescriptions#index_today", as: "index_today"
  get 'generate_order_pdf', to: 'prescriptions#generate_order_pdf', as: :generate_order_pdf

  resources :services do
    collection do
      get 'index_by_referral/:referral_id', action: "index_by_referral", as: "index_by_referral"
    end
    collection do
      get 'show_by_referral/:referral_id', action: "show_by_referral", as: "show_by_referral"
    end
  end
  resources :time_slots
  resources :regions
  resources :leads do
    collection do
      get 'absent'
      get 'attended'
      get 'cancelled'
      post 'search'
    end
  end
  post 'build_message/:lead_id', to: 'lead_messages#build_message', as: 'build_message'


end


