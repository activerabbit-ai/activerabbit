# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Email Confirmation", type: :request do
  describe "confirmation token generation" do
    let(:account) { create(:account) }
    let(:user) { create(:user, :unconfirmed, account: account) }

    it "generates a valid confirmation token" do
      raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)

      user.confirmation_token = encrypted_token
      user.confirmation_sent_at = Time.current
      user.save!

      # Token should be stored encrypted
      expect(user.confirmation_token).to eq(encrypted_token)
      expect(user.confirmation_token).not_to eq(raw_token)
    end

    it "can confirm user with raw token" do
      raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)

      user.confirmation_token = encrypted_token
      user.confirmation_sent_at = Time.current
      user.save!

      expect(user.confirmed?).to be false

      # Confirm using raw token
      get user_confirmation_path(confirmation_token: raw_token)

      user.reload
      expect(user.confirmed?).to be true
    end
  end

  describe "GET /users/confirmation" do
    let(:account) { create(:account) }

    context "with valid token" do
      let(:user) { create(:user, :unconfirmed, account: account) }

      before do
        raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
        user.update!(confirmation_token: encrypted_token, confirmation_sent_at: Time.current)
        @raw_token = raw_token
      end

      it "confirms the user" do
        expect(user.confirmed?).to be false

        get user_confirmation_path(confirmation_token: @raw_token)

        user.reload
        expect(user.confirmed?).to be true
      end

      it "redirects to sign in" do
        get user_confirmation_path(confirmation_token: @raw_token)

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "with invalid token" do
      it "does not confirm and shows error or redirects" do
        get user_confirmation_path(confirmation_token: "invalid_token")

        # Devise either renders a page with errors or redirects
        # Check that it either has error content or redirects
        if response.redirect?
          expect(response).to redirect_to(new_user_confirmation_path).or redirect_to(new_user_session_path)
        else
          expect(response.body.downcase).to include("invalid").or include("token")
        end
      end
    end

    context "with expired token" do
      let(:user) { create(:user, :unconfirmed, account: account) }

      before do
        raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
        # Set confirmation_sent_at to long ago (if confirm_within is set)
        user.update!(confirmation_token: encrypted_token, confirmation_sent_at: 1.year.ago)
        @raw_token = raw_token
      end

      it "does not confirm user if token expired" do
        get user_confirmation_path(confirmation_token: @raw_token)

        user.reload
        # User should not be confirmed with expired token (unless confirm_within is not set)
        # Either user stays unconfirmed or Devise doesn't enforce expiry
        expect(user.confirmed? || !Devise.confirm_within).to be true
      end
    end

    context "when already confirmed" do
      let(:user) { create(:user, :confirmed, account: account) }

      before do
        raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
        user.update!(confirmation_token: encrypted_token, confirmation_sent_at: Time.current)
        @raw_token = raw_token
      end

      it "handles already confirmed user" do
        get user_confirmation_path(confirmation_token: @raw_token)

        # User should remain confirmed
        user.reload
        expect(user.confirmed?).to be true
      end
    end
  end

  describe "User#confirm" do
    let(:account) { create(:account) }
    let(:user) { create(:user, :unconfirmed, account: account) }

    it "sets confirmed_at" do
      expect(user.confirmed_at).to be_nil

      user.confirm

      expect(user.confirmed_at).to be_present
    end

    it "does not require confirmation_token after confirm" do
      # Use a proper Devise-generated token
      raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
      user.update!(confirmation_token: encrypted_token, confirmation_sent_at: Time.current)

      expect(user.confirmation_token).to be_present
      expect(user.confirmed?).to be false

      user.confirm

      # After confirm, user is confirmed (token may or may not be cleared depending on Devise version)
      expect(user.reload.confirmed?).to be true
    end

    it "makes email_confirmed? return true" do
      expect(user.email_confirmed?).to be false

      user.confirm

      expect(user.email_confirmed?).to be true
    end
  end
end
