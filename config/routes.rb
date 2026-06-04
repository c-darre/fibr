Rails.application.routes.draw do
  devise_for :users
  root "pages#home"

  resources :analyses, only: [:index, :create, :show] do
    get :add_pictures, on: :member
    resources :messages, only: [:create] do
      post :create_with_pictures, on: :member
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
