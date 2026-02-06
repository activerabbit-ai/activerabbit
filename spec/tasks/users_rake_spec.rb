# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe "users rake tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  # Helper to capture stdout
  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  describe "users:send_confirmation_emails" do
    let(:task) { Rake::Task["users:send_confirmation_emails"] }

    before do
      task.reenable
      # Stub stdin to auto-answer "yes"
      allow($stdin).to receive(:gets).and_return("yes\n")
    end

    context "with unconfirmed users" do
      let!(:unconfirmed_user1) { create(:user, :unconfirmed, email: "unconfirmed1@example.com") }
      let!(:unconfirmed_user2) { create(:user, :unconfirmed, email: "unconfirmed2@example.com") }
      let!(:confirmed_user) { create(:user, :confirmed, email: "confirmed@example.com") }

      it "attempts to send confirmation emails to unconfirmed users" do
        # Allow the Devise mailer to be called (may or may not succeed depending on config)
        allow_any_instance_of(User).to receive(:send_confirmation_instructions).and_return(true)

        output = capture_output { task.invoke }

        # Task should find and process unconfirmed users
        expect(output).to include("Found 2 unconfirmed users")
        expect(output).to include("unconfirmed1@example.com")
        expect(output).to include("unconfirmed2@example.com")
      end

      it "updates confirmation_sent_at when send_confirmation_instructions is called" do
        # Stub the mailer to actually update confirmation_sent_at
        allow_any_instance_of(User).to receive(:send_confirmation_instructions) do |user|
          user.update_columns(confirmation_sent_at: Time.current)
        end

        task.invoke

        expect(unconfirmed_user1.reload.confirmation_sent_at).to be_present
        expect(unconfirmed_user2.reload.confirmation_sent_at).to be_present
      end
    end

    context "with no unconfirmed users" do
      let!(:confirmed_user) { create(:user, :confirmed) }

      it "reports no unconfirmed users and does nothing" do
        output = capture_output { task.invoke rescue nil } # exit may be called

        expect(output).to include("Found 0 unconfirmed users")
      end
    end

    context "when user answers no" do
      let!(:unconfirmed_user) { create(:user, :unconfirmed) }

      before do
        allow($stdin).to receive(:gets).and_return("no\n")
      end

      it "does not send any emails" do
        expect {
          begin
            task.invoke
          rescue SystemExit
            # Task calls exit on abort
          end
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end

  describe "users:confirm_all" do
    let(:task) { Rake::Task["users:confirm_all"] }

    before do
      task.reenable
      allow($stdin).to receive(:gets).and_return("yes\n")
    end

    context "with unconfirmed users" do
      let!(:unconfirmed_user1) { create(:user, :unconfirmed, email: "unconfirmed1@example.com") }
      let!(:unconfirmed_user2) { create(:user, :unconfirmed, email: "unconfirmed2@example.com") }
      let!(:confirmed_user) { create(:user, :confirmed, email: "confirmed@example.com") }

      it "confirms all unconfirmed users" do
        expect(unconfirmed_user1.confirmed?).to be false
        expect(unconfirmed_user2.confirmed?).to be false

        task.invoke

        expect(unconfirmed_user1.reload.confirmed?).to be true
        expect(unconfirmed_user2.reload.confirmed?).to be true
      end

      it "does not modify already confirmed users" do
        original_confirmed_at = confirmed_user.confirmed_at

        task.invoke

        expect(confirmed_user.reload.confirmed_at).to eq(original_confirmed_at)
      end

      it "does not send any emails" do
        expect {
          task.invoke
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context "with no unconfirmed users" do
      let!(:confirmed_user) { create(:user, :confirmed) }

      it "reports no users to confirm" do
        output = capture_output { task.invoke rescue nil } # exit may be called

        expect(output).to include("Found 0 unconfirmed users")
      end
    end
  end
end
