ClinicManagement::Engine.routes.draw do
  root 'invitations#new'
  resources :invitations do
    collection do
      get 'new_patient_fitted/:service_id', action: "new_patient_fitted", as: "new_patient_fitted"
      post 'create_patient_fitted', action: "create_patient_fitted", as: "create_patient_fitted"
    end
  end
  resources :lead_messages
  resources :appointments do
    member do
      patch :set_attendance
    end
    member do
      patch :cancel_attendance
    end
    member do 
      post :reschedule
    end
  end
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
    end
  end
  post 'build_message/:lead_id', to: 'lead_messages#build_message', as: 'build_message'


end


