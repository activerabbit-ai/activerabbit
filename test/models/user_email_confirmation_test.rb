require "test_helper"

class UserEmailConfirmationTest < ActiveSupport::TestCase
  setup do
    @confirmed_user = users(:owner)
    @unconfirmed_user = users(:unconfirmed_user)
    @oauth_user = users(:oauth_user)
  end

  # ============================================
  # email_confirmed? method tests
  # ============================================

  test "email_confirmed? returns true for user with confirmed_at" do
    assert @confirmed_user.confirmed_at.present?
    assert @confirmed_user.email_confirmed?
  end

  test "email_confirmed? returns false for user without confirmed_at or provider" do
    assert_nil @unconfirmed_user.confirmed_at
    assert_nil @unconfirmed_user.provider

    refute @unconfirmed_user.email_confirmed?
  end

  test "email_confirmed? returns true for OAuth user with provider" do
    assert @oauth_user.provider.present?
    assert @oauth_user.email_confirmed?
  end

  test "email_confirmed? returns true for OAuth user even without confirmed_at" do
    # Create a test user with provider but no confirmed_at
    user = User.new(
      email: "new_oauth@example.com",
      provider: "google",
      uid: "google123",
      account: @confirmed_user.account
    )

    assert_nil user.confirmed_at
    assert user.provider.present?
    assert user.email_confirmed?
  end

  # ============================================
  # Devise confirmable behavior tests
  # ============================================

  test "user can be confirmed" do
    refute @unconfirmed_user.confirmed?

    @unconfirmed_user.confirm

    assert @unconfirmed_user.confirmed?
    assert @unconfirmed_user.confirmed_at.present?
  end

  test "confirmed? returns true after setting confirmed_at" do
    @unconfirmed_user.update!(confirmed_at: Time.current)

    assert @unconfirmed_user.confirmed?
  end

  test "confirmation_token can be generated" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)

    assert raw_token.present?
    assert encrypted_token.present?
    refute_equal raw_token, encrypted_token
  end

  test "confirmation_token can be set on user" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)

    @unconfirmed_user.update!(
      confirmation_token: encrypted_token,
      confirmation_sent_at: Time.current
    )

    assert_equal encrypted_token, @unconfirmed_user.confirmation_token
  end
end
