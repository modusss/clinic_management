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
  end
  resources :services
  resources :time_slots
  resources :regions
  resources :leads
end
