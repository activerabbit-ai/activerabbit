require "test_helper"

class AiRequestTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @user = users(:owner)
  end

  # Associations

  test "belongs to account" do
    association = AiRequest.reflect_on_association(:account)
    assert_equal :belongs_to, association.macro
  end

  test "belongs to user" do
    association = AiRequest.reflect_on_association(:user)
    assert_equal :belongs_to, association.macro
  end

  # Fixtures

  test "ai_requests fixture is valid" do
    ai_request = ai_requests(:summary)
    assert ai_request.valid?
  end

  # Creation

  test "creates ai_request with required attributes" do
    ai_request = AiRequest.new(
      account: @account,
      user: @user,
      request_type: "summary",
      occurred_at: Time.current
    )

    assert ai_request.save
    assert ai_request.persisted?
  end
end
