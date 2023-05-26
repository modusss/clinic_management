ClinicManagement::Engine.routes.draw do
  resources :invitations
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
  resources :services
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


