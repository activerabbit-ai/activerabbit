require 'sidekiq/web'

Rails.application.routes.draw do
  namespace :admin do
    root "dashboard#index"
    get "dashboard", to: "dashboard#index"
    get "deploys", to: "deploys#index"
    get "errors", to: "errors#index"
    get "performance", to: "performance#index"
    get "security", to: "security#index"
    get "logs", to: "logs#index"
    get "settings", to: "settings#index"

    # Projects management
    resources :projects do
      member do
        post :regenerate_token
      end

      # Nested resources for project-specific management
      resources :issues do
        member do
          patch :update  # For resolve/ignore/reopen actions
        end
        collection do
          post :bulk_action
        end
      end

      resources :events do
        collection do
          post :bulk_delete
          post :cleanup_old
        end
      end

      resources :alert_rules do
        member do
          post :toggle
          post :test_alert
        end
      end

      # Performance monitoring
      get 'performance', to: 'performance#index'
      get 'performance/sql_fingerprints', to: 'performance#sql_fingerprints'
      get 'performance/sql_fingerprints/:id', to: 'performance#sql_fingerprint', as: 'performance_sql_fingerprint'
      post 'performance/sql_fingerprints/:id/create_pr', to: 'performance#create_n_plus_one_pr', as: 'create_n_plus_one_pr'
    end

    # Global performance overview (no project context)
    get 'performance', to: 'performance#index'
  end
  devise_for :users
  root "home#index"

  # Sidekiq Web UI (protect this in production)
  mount Sidekiq::Web => '/sidekiq'

  # Pay gem routes for webhooks
  mount Pay::Engine, at: "/payments", as: :pay_engine

  # Subscription management
  resources :subscriptions, only: [:new, :create, :show, :destroy]

  # API routes for data ingestion
  namespace :api do
    namespace :v1 do
      # Event ingestion endpoints
      post 'events/errors', to: 'events#create_error'
      post 'events/performance', to: 'events#create_performance'
      post 'events/batch', to: 'events#create_batch'

      # Release tracking
      resources :releases, only: [:create, :index, :show] do
        member do
          post :trigger_regression_check
        end
      end
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
