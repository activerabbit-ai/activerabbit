require 'sidekiq/web'

Rails.application.routes.draw do
  devise_for :users
  root "dashboard#index"

  # Onboarding routes for new users
  get 'onboarding/welcome', to: 'onboarding#welcome', as: 'onboarding_welcome'
  get 'onboarding/new_project', to: 'onboarding#new_project', as: 'onboarding_new_project'
  post 'onboarding/create_project', to: 'onboarding#create_project', as: 'onboarding_create_project'
  get 'onboarding/install_gem/:project_id', to: 'onboarding#install_gem', as: 'onboarding_install_gem'
  post 'onboarding/verify_gem/:project_id', to: 'onboarding#verify_gem', as: 'onboarding_verify_gem'

  # Top-level replacements for admin pages (no /admin in URLs)
  get 'dashboard', to: 'dashboard#index', as: 'dashboard'
  get 'deploys', to: 'deploys#index', as: 'deploys'
  get 'errors', to: 'errors#index', as: 'errors'
  resources :errors, only: [:show, :update, :destroy]
  get 'security', to: 'security#index', as: 'security'
  get 'settings', to: 'settings#index', as: 'settings'
  patch 'settings/update_slack_settings', to: 'settings#update_slack_settings', as: 'update_slack_settings_settings'
  patch 'settings/update_user_slack_preferences', to: 'settings#update_user_slack_preferences', as: 'update_user_slack_preferences_settings'
  post 'settings/test_slack_notification', to: 'settings#test_slack_notification', as: 'test_slack_notification_settings'

  # Account-wide settings
  resource :account_settings, path: 'account/settings', only: [:show, :update] do
    post :test_notification
    patch :update_user_preferences
  end

  # Top-level Performance routes (no /admin or /projects/:id required)
  get 'performance', to: 'performance#index', as: 'performance'
  get 'performance/actions/:target', to: 'performance#action_detail', as: 'performance_action_detail'
  get 'performance/sql_fingerprints', to: 'performance#sql_fingerprints', as: 'performance_sql_fingerprints'
  get 'performance/sql_fingerprints/:id', to: 'performance#sql_fingerprint', as: 'performance_sql_fingerprint'
  post 'performance/sql_fingerprints/:id/create_pr', to: 'performance#create_n_plus_one_pr', as: 'performance_create_n_plus_one_pr'

  # Project-scoped Performance routes at top-level (no /admin)
  get 'projects/:project_id/performance', to: 'performance#index', as: 'project_performance'
  get 'projects/:project_id/performance/:id', to: 'performance#show', as: 'project_performance_issue'
  get 'projects/:project_id/performance/actions/:target', to: 'performance#action_detail', as: 'project_performance_action_detail'
  get 'projects/:project_id/performance/sql_fingerprints', to: 'performance#sql_fingerprints', as: 'project_performance_sql_fingerprints'
  get 'projects/:project_id/performance/sql_fingerprints/:id', to: 'performance#sql_fingerprint', as: 'project_performance_sql_fingerprint'
  post 'projects/:project_id/performance/sql_fingerprints/:id/create_pr', to: 'performance#create_n_plus_one_pr', as: 'project_performance_create_n_plus_one_pr'

  # Top-level Logs route (no /admin)
  get 'logs', to: 'logs#index', as: 'logs'

  # Project-scoped Errors routes (no /admin)
  get 'projects/:project_id/errors', to: 'errors#index', as: 'project_errors'
  get 'projects/:project_id/errors/:id', to: 'errors#show', as: 'project_error'
  patch 'projects/:project_id/errors/:id', to: 'errors#update'
  delete 'projects/:project_id/errors/:id', to: 'errors#destroy'

  # Projects management (non-admin)
  # Note: projects index page is hidden - dashboard shows all projects instead
  resources :projects, except: [:index] do
    member do
      post :regenerate_token
    end

    resource :settings, controller: 'project_settings', only: [:show, :update] do
      post :test_notification
    end

    resources :issues do
      member do
        patch :update
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
  end

  # Project-scoped Security, Logs, Deploys
  get 'projects/:project_id/security', to: 'security#index', as: 'project_security'
  get 'projects/:project_id/logs', to: 'logs#index', as: 'project_logs'
  get 'projects/:project_id/deploys', to: 'deploys#index', as: 'project_deploys'

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

      # Connection test endpoint
      post 'test/connection', to: 'events#test_connection'

      # Release tracking
      resources :releases, only: [:create, :index, :show] do
        member do
          post :trigger_regression_check
        end
      end
    end
  end

  # Test endpoints for ActiveRabbit self-monitoring
  get 'test_monitoring', to: 'test_monitoring#index'
  get 'test_monitoring/error', to: 'test_monitoring#test_error'
  get 'test_monitoring/performance', to: 'test_monitoring#test_performance'
  get 'test_monitoring/manual', to: 'test_monitoring#test_manual_tracking'
  get 'test_monitoring/connection', to: 'test_monitoring#test_connection'

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  # Using dedicated HealthCheckController that bypasses all authentication
  # IMPORTANT: This must come BEFORE the slug-based routes to avoid conflicts
  get "up" => "health_check#show", as: :rails_health_check

  # Simple test endpoint to debug deployment health check issues
  get "health_test" => "test_monitoring#health_test"

  # Slug-based project routes (e.g., /remotely/errors, /remotely/performance)
  # These must come after other specific routes to avoid conflicts
  get ':project_slug', to: 'dashboard#project_dashboard', as: 'project_dashboard'
  get ':project_slug/errors', to: 'errors#index', as: 'project_slug_errors'
  get ':project_slug/errors/:id', to: 'errors#show', as: 'project_slug_error'
  get ':project_slug/performance', to: 'performance#index', as: 'project_slug_performance'
  get ':project_slug/deploys', to: 'deploys#index', as: 'project_slug_deploys'
  get ':project_slug/settings', to: 'project_settings#show', as: 'project_slug_settings'

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
