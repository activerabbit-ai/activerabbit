require 'sidekiq/web'

Rails.application.routes.draw do
  namespace :admin do
    root "dashboard#index"
    get "dashboard", to: "dashboard#index"
    get "deploys", to: "deploys#index"
    get "errors", to: "errors#index"
    get "errors/:id", to: "errors#show", as: "error"
    patch "errors/:id", to: "errors#update"
    delete "errors/:id", to: "errors#destroy"
    get "performance", to: "performance#index"
    get "security", to: "security#index"
    get "logs", to: "logs#index"
    get "settings", to: "settings#index"

    # Public demo endpoints (no auth required)
    get "public/errors", to: "public#errors"

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
      get 'performance/actions/:target', to: 'performance#action_detail', as: 'performance_action_detail'
      get 'performance/sql_fingerprints', to: 'performance#sql_fingerprints'
      get 'performance/sql_fingerprints/:id', to: 'performance#sql_fingerprint', as: 'performance_sql_fingerprint'
      post 'performance/sql_fingerprints/:id/create_pr', to: 'performance#create_n_plus_one_pr', as: 'create_n_plus_one_pr'
    end

    # Global performance overview (no project context)
    get 'performance', to: 'performance#index'
  end
  devise_for :users
  root "home#index"

  # Top-level replacements for admin pages (no /admin in URLs)
  get 'dashboard', to: 'admin/dashboard#index', as: 'dashboard'
  get 'deploys', to: 'admin/deploys#index', as: 'deploys'
  get 'errors', to: 'admin/errors#index', as: 'errors'
  get 'security', to: 'admin/security#index', as: 'security'
  get 'settings', to: 'admin/settings#index', as: 'settings'

  # Top-level Performance routes (no /admin or /projects/:id required)
  get 'performance', to: 'admin/performance#index', as: 'performance'
  get 'performance/actions/:target', to: 'admin/performance#action_detail', as: 'performance_action_detail'
  get 'performance/sql_fingerprints', to: 'admin/performance#sql_fingerprints', as: 'performance_sql_fingerprints'
  get 'performance/sql_fingerprints/:id', to: 'admin/performance#sql_fingerprint', as: 'performance_sql_fingerprint'
  post 'performance/sql_fingerprints/:id/create_pr', to: 'admin/performance#create_n_plus_one_pr', as: 'performance_create_n_plus_one_pr'

  # Project-scoped Performance routes at top-level (no /admin)
  get 'projects/:project_id/performance', to: 'admin/performance#index', as: 'project_performance'
  get 'projects/:project_id/performance/actions/:target', to: 'admin/performance#action_detail', as: 'project_performance_action_detail'
  get 'projects/:project_id/performance/sql_fingerprints', to: 'admin/performance#sql_fingerprints', as: 'project_performance_sql_fingerprints'
  get 'projects/:project_id/performance/sql_fingerprints/:id', to: 'admin/performance#sql_fingerprint', as: 'project_performance_sql_fingerprint'
  post 'projects/:project_id/performance/sql_fingerprints/:id/create_pr', to: 'admin/performance#create_n_plus_one_pr', as: 'project_performance_create_n_plus_one_pr'

  # Top-level Logs route (no /admin)
  get 'logs', to: 'admin/logs#index', as: 'logs'

  # Project-scoped Errors routes (no /admin)
  get 'projects/:project_id/errors', to: 'admin/errors#index', as: 'project_errors'
  get 'projects/:project_id/errors/:id', to: 'admin/errors#show', as: 'project_error'
  patch 'projects/:project_id/errors/:id', to: 'admin/errors#update'
  delete 'projects/:project_id/errors/:id', to: 'admin/errors#destroy'

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
