# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devise::Mailer, type: :mailer do
  describe "#confirmation_instructions" do
    let(:account) { create(:account) }
    let(:user) { create(:user, :unconfirmed, account: account) }
    let(:token) { "test_confirmation_token_123" }

    before do
      # Ensure routes and Devise mappings are properly loaded
      Rails.application.reload_routes!
      Rails.application.routes.default_url_options[:host] = 'localhost'
    end

    subject(:mail) { described_class.confirmation_instructions(user, token) }

    it "renders the headers" do
      expect(mail.to).to eq([user.email])
      expect(mail.from.first).to include("activerabbit")
    end

    it "includes ActiveRabbit branding" do
      expect(mail.body.encoded).to include("ActiveRabbit")
    end

    it "includes thank you message" do
      expect(mail.body.encoded).to include("Thanks for creating an account")
    end

    it "includes confirmation link" do
      expect(mail.body.encoded).to include("confirmation_token=#{token}")
    end

    it "includes user email" do
      expect(mail.body.encoded).to include(user.email)
    end

    it "includes confirm button" do
      expect(mail.body.encoded).to include("Confirm Email Address")
    end

    it "includes safety note" do
      expect(mail.body.encoded).to include("didn't create an account")
      expect(mail.body.encoded).to include("safely ignore")
    end

    it "includes AI-Powered Error Tracking tagline" do
      expect(mail.body.encoded).to include("AI-Powered Error Tracking for Rails")
    end

    it "has proper HTML structure" do
      expect(mail.body.encoded).to include("<!DOCTYPE html>")
      expect(mail.body.encoded).to include("<html>")
      expect(mail.body.encoded).to include("</html>")
    end

    it "has styled button" do
      expect(mail.body.encoded).to include('class="button"')
    end
  end
end
