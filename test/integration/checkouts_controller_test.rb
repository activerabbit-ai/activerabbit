require "test_helper"

class CheckoutsControllerTest < ActionDispatch::IntegrationTest
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
    post checkouts_path, params: { plan: "starter" }
    assert_redirected_to new_user_session_path
  end

  test "POST create with free plan updates account" do
    post checkouts_path, params: { plan: "free" }

    assert_redirected_to dashboard_path
    @account.reload
    assert_equal "free", @account.current_plan
  end

  test "POST create with free plan sets success message" do
    post checkouts_path, params: { plan: "free" }

    assert_redirected_to dashboard_path
    assert flash[:notice].present?
  end

  test "POST create with paid plan requires Stripe checkout" do
    # Stub CheckoutCreator to return a mock checkout session
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")

    CheckoutCreator.stub(:new, ->(**args) {
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "starter", interval: "month" }

      # Should redirect to Stripe checkout
      assert_response :see_other
    end
  end

  test "POST create with interval parameter" do
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")
    interval_passed = nil

    CheckoutCreator.stub(:new, ->(**args) {
      interval_passed = args[:interval]
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "starter", interval: "year" }
    end

    assert_equal "year", interval_passed
  end

  test "POST create with ai parameter" do
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")
    ai_passed = nil

    CheckoutCreator.stub(:new, ->(**args) {
      ai_passed = args[:ai]
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "starter", ai: "true" }
    end

    assert ai_passed.present?
  end

  test "POST create handles errors gracefully" do
    CheckoutCreator.stub(:new, ->(**args) {
      raise StandardError, "Stripe error"
    }) do
      post checkouts_path, params: { plan: "starter" }

      assert_redirected_to settings_path
      assert flash[:alert].present?
    end
  end
end
