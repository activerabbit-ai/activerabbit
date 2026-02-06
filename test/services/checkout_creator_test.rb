require "test_helper"

class CheckoutCreatorTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @user = users(:owner)

    # Set required ENV variables
    ENV["STRIPE_PRICE_DEV_MONTHLY"] = "price_dev_m"
    ENV["STRIPE_PRICE_DEV_ANNUAL"] = "price_dev_y"
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"
    ENV["STRIPE_PRICE_TEAM_ANNUAL"] = "price_team_y"
    ENV["STRIPE_PRICE_ENT_MONTHLY"] = "price_ent_m"
    ENV["STRIPE_PRICE_ENT_ANNUAL"] = "price_ent_y"
    ENV["STRIPE_PRICE_AI_MONTHLY"] = "price_ai_m"
    ENV["STRIPE_PRICE_AI_ANNUAL"] = "price_ai_y"
    ENV["STRIPE_PRICE_AI_OVERAGE_METERED"] = "price_ai_over_m"
    ENV["APP_HOST"] = "localhost:3000"

    # Stub Stripe
    stub_request(:post, /api\.stripe\.com/).to_return(
      status: 200,
      body: { url: "https://stripe.example/session" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  test "creates checkout creator with required params" do
    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month",
      ai: false
    )

    assert creator.is_a?(CheckoutCreator)
  end

  # test "uses AI monthly price when interval is month" do
  #   # Requires Pay::Customer setup - more complex setup with Pay gem needed
  # end
end
