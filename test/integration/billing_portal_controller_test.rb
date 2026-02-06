require "test_helper"

class BillingPortalControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires authentication" do
    sign_out @user
    post billing_portal_index_path
    assert_redirected_to new_user_session_path
  end

  test "POST create redirects to Stripe billing portal" do
    mock_session = OpenStruct.new(url: "https://billing.stripe.com/session")
    mock_processor = OpenStruct.new(
      blank?: false,
      processor_id: "cus_test123"
    )

    @user.stub(:payment_processor, mock_processor) do
      @user.stub(:set_payment_processor, true) do
        Stripe::BillingPortal::Session.stub(:create, mock_session) do
          post billing_portal_index_path
        end
      end
    end

    # Should redirect to Stripe
    assert_response :redirect
  end

  test "POST create handles Stripe error gracefully" do
    mock_processor = OpenStruct.new(
      blank?: false,
      processor_id: "cus_test123"
    )

    @user.stub(:payment_processor, mock_processor) do
      @user.stub(:set_payment_processor, true) do
        Stripe::BillingPortal::Session.stub(:create, ->(*args) {
          raise Stripe::InvalidRequestError.new("Test error", "param")
        }) do
          post billing_portal_index_path
        end
      end
    end

    # Should redirect to settings with error
    assert_redirected_to settings_path
    assert flash[:alert].present?
  end
end
