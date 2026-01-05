require 'rails_helper'

RSpec.describe SendWelcomeEmailJob, type: :job do
  # Uses @test_account from spec/support/acts_as_tenant.rb
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:reset_token) { "test_reset_token_123" }

  describe "#perform" do
    let(:mock_mail) { double("Mail", deliver_now: true) }

    it "sends welcome email to the user" do
      expect(UserMailer).to receive(:welcome_and_setup_password)
        .with(user, reset_token)
        .and_return(mock_mail)

      described_class.new.perform(user.id, reset_token)
    end

    it "sends email with correct recipient" do
      expect(UserMailer).to receive(:welcome_and_setup_password)
        .with(user, reset_token)
        .and_return(mock_mail)

      described_class.new.perform(user.id, reset_token)
    end

    it "calls deliver_now on the mailer" do
      allow(UserMailer).to receive(:welcome_and_setup_password).and_return(mock_mail)
      expect(mock_mail).to receive(:deliver_now)

      described_class.new.perform(user.id, reset_token)
    end

    context "when user is not found" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          described_class.new.perform(-1, reset_token)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "job configuration" do
    it "is enqueued in the default queue" do
      expect(described_class.sidekiq_options["queue"]).to eq(:default)
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end
