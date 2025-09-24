RSpec.configure do |config|
  config.before(:each) do
    @test_account = create(:account)
    ActsAsTenant.current_tenant = @test_account
  end

  config.after(:each) do
    ActsAsTenant.current_tenant = nil
  end
end


