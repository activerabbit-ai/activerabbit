require "test_helper"

class DeviseMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:unconfirmed_user)
    @token = "test_confirmation_token_123"
  end

  test "confirmation_instructions renders correct headers" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_equal [@user.email], mail.to
    assert mail.from.first.include?("activerabbit")
  end

  test "confirmation_instructions includes ActiveRabbit branding" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, "ActiveRabbit"
  end

  test "confirmation_instructions includes thank you message" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, "Thanks for creating an account"
  end

  test "confirmation_instructions includes confirmation link" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, "confirmation_token=#{@token}"
  end

  test "confirmation_instructions includes user email" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, @user.email
  end

  test "confirmation_instructions includes confirm button" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, "Confirm Email Address"
  end

  test "confirmation_instructions has proper HTML structure" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, "<!DOCTYPE html>"
    assert_includes mail.body.encoded, "<html>"
    assert_includes mail.body.encoded, "</html>"
  end

  test "confirmation_instructions includes logo image" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    # Asset path includes hash, so just check for favicon-512
    assert_includes mail.body.encoded, "favicon-512"
  end

  test "confirmation_instructions includes gradient header" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    # Check for gradient styling
    assert_includes mail.body.encoded, "linear-gradient"
    assert_includes mail.body.encoded, "#667eea"
  end

  test "confirmation_instructions includes safety note" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, "didn't create an account"
    assert_includes mail.body.encoded, "safely ignore"
  end

  test "confirmation_instructions includes AI-Powered tagline" do
    mail = Devise::Mailer.confirmation_instructions(@user, @token)

    assert_includes mail.body.encoded, "AI-Powered Error Tracking"
  end
end
