# ActsAsTenant configuration
ActsAsTenant.configure do |config|
  # Don't require tenant in development console for easier testing
  config.require_tenant = -> do
    return false if defined?(Rails::Console)
    return false if Rails.env.test?
    true
  end
end

# Set default tenant in development console
if Rails.env.development?
  SET_TENANT_PROC = lambda do
    if defined?(Rails::Console)
      if Account.exists?
        puts '> ActsAsTenant.current_tenant = Account.first'
        ActsAsTenant.current_tenant = Account.first
      else
        puts "> No accounts found. Create one with: Account.create!(name: 'Test Account')"
      end
    end
  end

  Rails.application.configure do
    # Set the tenant to the first account in development on load
    config.after_initialize do
      SET_TENANT_PROC.call
    end

    # Reset the tenant after calling 'reload!' in the console
    ActiveSupport::Reloader.to_complete do
      SET_TENANT_PROC.call
    end
  end
end
