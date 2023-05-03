ClinicManagement::Engine.routes.draw do
  resources :invitations
  resources :appointments
  resources :services
  resources :time_slots
  resources :regions
  resources :leads
end
