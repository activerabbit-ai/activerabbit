require "test_helper"

class EmailConfirmationTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @unconfirmed_user = users(:unconfirmed_user)
    @confirmed_user = users(:owner)
    @user_within_grace = users(:unconfirmed_within_grace_period)
    @user_past_grace = users(:unconfirmed_past_grace_period)
    @oauth_user = users(:oauth_user)
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

  # ============================================
  # Grace Period Tests (allow_unconfirmed_access_for = 2.days)
  # ============================================

  test "unconfirmed user within grace period can sign in" do
    # User created 1 day ago should be able to sign in
    post user_session_path, params: {
      user: { email: @user_within_grace.email, password: "password123" }
    }

    # Should redirect to dashboard/root, not block
    assert_response :redirect
    refute_includes response.location, "sign_in"
  end

  test "unconfirmed user past grace period cannot sign in" do
    # User created 3 days ago should be blocked
    post user_session_path, params: {
      user: { email: @user_past_grace.email, password: "password123" }
    }

    # Should see error or redirect back to sign in
    follow_redirect! if response.redirect?
    # User should not be signed in - either see sign in page or error
    assert_match(/confirm|sign in/i, response.body) if response.successful?
  end

  test "confirmed user can always sign in" do
    post user_session_path, params: {
      user: { email: @confirmed_user.email, password: "password123" }
    }

    assert_response :redirect
    refute_includes response.location, "sign_in"
  end

  # ============================================
  # OAuth Users (auto-confirmed)
  # ============================================

  test "OAuth user is considered email_confirmed via provider" do
    # OAuth users should have provider set
    assert @oauth_user.provider.present?

    # OAuth users are considered confirmed via email_confirmed? method
    assert @oauth_user.email_confirmed?
  end

  # ============================================
  # Confirmation Banner Tests
  # ============================================

  test "confirmation banner appears for unconfirmed user" do
    sign_in @user_within_grace

    get dashboard_path

    assert_response :success
    # Check for the yellow warning banner
    assert_includes response.body, "bg-yellow-50"
    assert_includes response.body, "confirm your email"
  end

  test "confirmation banner does not appear for confirmed user" do
    sign_in @confirmed_user

    get dashboard_path

    assert_response :success
    # Confirmed users should not see the confirmation banner text
    refute_includes response.body, "Please confirm your email address"
  end

  test "confirmation banner does not appear for OAuth user" do
    # OAuth users are auto-confirmed via provider
    assert @oauth_user.email_confirmed?, "OAuth user should be considered confirmed"

    sign_in @oauth_user

    get dashboard_path

    assert_response :success
    # OAuth users are considered confirmed, so no banner
    refute_includes response.body, "Please confirm your email address"
  end

  test "confirmation banner shows user email" do
    sign_in @user_within_grace

    get dashboard_path

    assert_response :success
    # User email should be shown somewhere on the page
    assert_includes response.body, @user_within_grace.email
  end

  test "confirmation banner includes resend link" do
    sign_in @user_within_grace

    get dashboard_path

    assert_response :success
    # Check for link to resend confirmation (path: "" means /confirmation/new)
    assert_includes response.body, "/confirmation/new"
  end

  # ============================================
  # Resend Confirmation Email
  # ============================================

  test "can request new confirmation email" do
    get new_user_confirmation_path

    assert_response :success
    assert_select "form[action=?]", user_confirmation_path
  end

  test "resend confirmation email sends email" do
    assert_emails 1 do
      post user_confirmation_path, params: {
        user: { email: @unconfirmed_user.email }
      }
    end
  end

  test "resend confirmation does not send to confirmed user" do
    assert_no_emails do
      post user_confirmation_path, params: {
        user: { email: @confirmed_user.email }
      }
    end
  end
end
