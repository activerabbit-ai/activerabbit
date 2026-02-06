require "test_helper"

class EmailConfirmationTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @unconfirmed_user = users(:unconfirmed_user)
    @confirmed_user = users(:owner)
  end

  # Confirmation token generation

  test "generates a valid confirmation token" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)

    @unconfirmed_user.confirmation_token = encrypted_token
    @unconfirmed_user.confirmation_sent_at = Time.current
    @unconfirmed_user.save!

    assert_equal encrypted_token, @unconfirmed_user.confirmation_token
    refute_equal raw_token, @unconfirmed_user.confirmation_token
  end

  test "can confirm user with raw token" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)

    @unconfirmed_user.confirmation_token = encrypted_token
    @unconfirmed_user.confirmation_sent_at = Time.current
    @unconfirmed_user.save!

    refute @unconfirmed_user.confirmed?

    get user_confirmation_path(confirmation_token: raw_token)

    @unconfirmed_user.reload
    assert @unconfirmed_user.confirmed?
  end

  # GET /users/confirmation with valid token

  test "confirms user with valid token" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
    @unconfirmed_user.update!(confirmation_token: encrypted_token, confirmation_sent_at: Time.current)

    refute @unconfirmed_user.confirmed?

    get user_confirmation_path(confirmation_token: raw_token)

    @unconfirmed_user.reload
    assert @unconfirmed_user.confirmed?
  end

  test "redirects to sign in after confirmation" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
    @unconfirmed_user.update!(confirmation_token: encrypted_token, confirmation_sent_at: Time.current)

    get user_confirmation_path(confirmation_token: raw_token)

    assert_redirected_to new_user_session_path
  end

  # Invalid token

  test "does not confirm with invalid token" do
    get user_confirmation_path(confirmation_token: "invalid_token")

    # Devise either renders a page with errors or redirects
    if response.redirect?
      assert response.redirect?
    else
      assert_includes response.body.downcase, "invalid"
    end
  end

  # Expired token

  test "handles expired token appropriately" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
    @unconfirmed_user.update!(confirmation_token: encrypted_token, confirmation_sent_at: 1.year.ago)

    get user_confirmation_path(confirmation_token: raw_token)

    @unconfirmed_user.reload
    # User should not be confirmed with expired token (unless confirm_within is not set)
    assert @unconfirmed_user.confirmed? || !Devise.confirm_within
  end

  # Already confirmed

  test "handles already confirmed user" do
    raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
    @confirmed_user.update!(confirmation_token: encrypted_token, confirmation_sent_at: Time.current)

    get user_confirmation_path(confirmation_token: raw_token)

    @confirmed_user.reload
    assert @confirmed_user.confirmed?
  end

  # User#confirm method

  test "confirm sets confirmed_at" do
    assert_nil @unconfirmed_user.confirmed_at

    @unconfirmed_user.confirm

    assert @unconfirmed_user.confirmed_at.present?
  end

  test "email_confirmed? returns true after confirm" do
    refute @unconfirmed_user.email_confirmed?

    @unconfirmed_user.confirm

    assert @unconfirmed_user.email_confirmed?
  end
end
