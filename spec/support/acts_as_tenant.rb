RSpec.configure do |config|
  config.before(:each) do |example|
    # Skip tenant setup for API tests - they manage their own tenant
    next if example.metadata[:api]

    @test_account = create(:account)
    ActsAsTenant.current_tenant = @test_account
  end

  config.after(:each) do
    ActsAsTenant.current_tenant = nil
  end
end
