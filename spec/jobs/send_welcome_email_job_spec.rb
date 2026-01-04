require 'rails_helper'

RSpec.describe SendWelcomeEmailJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:reset_token) { "test_reset_token_123" }

  describe "#perform" do
    it "sends welcome email to the user" do
      expect {
        described_class.new.perform(user.id, reset_token)
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sends email with correct recipient" do
      described_class.new.perform(user.id, reset_token)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([user.email])
    end

    it "sends email with welcome subject" do
      described_class.new.perform(user.id, reset_token)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to include("Welcome")
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
