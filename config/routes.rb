Rails.application.routes.draw do
  devise_for :users
  root "pages#home"

  resources :analyses, only: [:index, :create, :show] do
    get :add_pictures, on: :member
    get :questionnary, on: :member
    post :start_questionnary, on: :member
    resources :chats, only: [] do
      resources :messages, only: [:create]
    end
    resource :discussion, only: [:show], controller: :discussions
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
