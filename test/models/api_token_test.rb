require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  # authenticate

  test "authenticate returns token and increments usage when valid" do
    token = api_tokens(:default)
    original_count = token.usage_count

    result = ApiToken.authenticate(token.token)

    assert_equal token, result
    assert_equal original_count + 1, token.reload.usage_count
  end

  test "authenticate returns nil when token is missing" do
    assert_nil ApiToken.authenticate(nil)
  end

  test "authenticate returns nil when token is invalid" do
    assert_nil ApiToken.authenticate("invalid_token")
  end

  # mask_token

  test "mask_token masks middle characters" do
    token = api_tokens(:default)
    # Set a known token value for testing
    token.update!(token: "a" * 64)

    masked = token.mask_token

    assert masked.start_with?("aaaaaaaa")
    assert masked.end_with?("aaaaaaaa")
    assert_includes masked, "********"
  end

  # revoke and activate

  test "revoke sets active to false" do
    token = api_tokens(:default)
    token.revoke!
    refute token.active
  end

  test "activate sets active to true" do
    token = api_tokens(:inactive_token)
    token.activate!
    assert token.active
  end
end
