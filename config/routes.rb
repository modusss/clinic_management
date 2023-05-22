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
  resources :leads do
    collection do
      get 'absent'
      get 'attended'
      get 'cancelled'
    end
  end
  post 'replace_lead_attributes/:order_id', to: 'lead_messages#replace_lead_attributes', as: 'replace_lead_attributes'


end


