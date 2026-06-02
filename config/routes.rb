Rails.application.routes.draw do
  devise_for :users
  root "pages#home"

  resources :analyses, only: [:create, :show] do
    get :add_pictures, on: :member
    resources :messages, only: [:create]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
