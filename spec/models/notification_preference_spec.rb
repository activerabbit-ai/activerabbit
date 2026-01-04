require 'rails_helper'

RSpec.describe NotificationPreference, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }

  describe "validations" do
    let(:notification_preference) { create(:notification_preference, project: project) }

    it "is valid with valid attributes" do
      expect(notification_preference).to be_valid
    end

    it "is not valid without a project" do
      notification_preference.project = nil
      expect(notification_preference).to_not be_valid
    end

    it "is not valid without an alert type" do
      notification_preference.alert_type = nil
      expect(notification_preference).to_not be_valid
    end

    it "is not valid without a frequency" do
      notification_preference.frequency = nil
      expect(notification_preference).to_not be_valid
    end

    it "validates alert_type is in ALERT_TYPES" do
      notification_preference.alert_type = "invalid_type"
      expect(notification_preference).to_not be_valid
    end

    it "validates frequency is in FREQUENCIES" do
      notification_preference.frequency = "invalid_frequency"
      expect(notification_preference).to_not be_valid
    end
  end

  describe "FREQUENCIES constant" do
    it "includes every_2_hours" do
      expect(NotificationPreference::FREQUENCIES).to include("every_2_hours")
    end

    it "includes all expected frequencies" do
      expect(NotificationPreference::FREQUENCIES).to match_array(%w[
        immediate
        every_30_minutes
        every_2_hours
        first_in_deploy
        after_close
      ])
    end
  end

  describe "#can_send_now?" do
    subject(:preference) do
      create(:notification_preference,
        project: project,
        enabled: true,
        frequency: frequency,
        last_sent_at: last_sent_at
      )
    end

    context "when disabled" do
      let(:frequency) { "immediate" }
      let(:last_sent_at) { nil }

      it "returns false" do
        preference.update!(enabled: false)
        expect(preference.can_send_now?).to be false
      end
    end

    context "with immediate frequency" do
      let(:frequency) { "immediate" }

      context "when never sent" do
        let(:last_sent_at) { nil }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end

      context "when sent recently" do
        let(:last_sent_at) { 1.minute.ago }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end
    end

    context "with every_30_minutes frequency" do
      let(:frequency) { "every_30_minutes" }

      context "when never sent" do
        let(:last_sent_at) { nil }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end

      context "when sent 10 minutes ago" do
        let(:last_sent_at) { 10.minutes.ago }

        it "returns false" do
          expect(preference.can_send_now?).to be false
        end
      end

      context "when sent 31 minutes ago" do
        let(:last_sent_at) { 31.minutes.ago }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end
    end

    context "with every_2_hours frequency" do
      let(:frequency) { "every_2_hours" }

      context "when never sent" do
        let(:last_sent_at) { nil }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end

      context "when sent 30 minutes ago" do
        let(:last_sent_at) { 30.minutes.ago }

        it "returns false" do
          expect(preference.can_send_now?).to be false
        end
      end

      context "when sent 1 hour ago" do
        let(:last_sent_at) { 1.hour.ago }

        it "returns false" do
          expect(preference.can_send_now?).to be false
        end
      end

      context "when sent 2 hours and 1 minute ago" do
        let(:last_sent_at) { 121.minutes.ago }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end
    end

    context "with first_in_deploy frequency" do
      let(:frequency) { "first_in_deploy" }

      context "when never sent" do
        let(:last_sent_at) { nil }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end

      context "when already sent" do
        let(:last_sent_at) { 1.hour.ago }

        it "returns false" do
          expect(preference.can_send_now?).to be false
        end
      end
    end

    context "with after_close frequency" do
      let(:frequency) { "after_close" }

      context "when never sent" do
        let(:last_sent_at) { nil }

        it "returns true" do
          expect(preference.can_send_now?).to be true
        end
      end

      context "when already sent" do
        let(:last_sent_at) { 1.day.ago }

        it "returns false" do
          expect(preference.can_send_now?).to be false
        end
      end
    end
  end

  describe "#mark_sent!" do
    let(:preference) do
      create(:notification_preference,
        project: project,
        enabled: true,
        last_sent_at: nil
      )
    end

    it "updates last_sent_at to current time" do
      freeze_time do
        expect { preference.mark_sent! }
          .to change { preference.reload.last_sent_at }
          .from(nil)
          .to(Time.current)
      end
    end
  end
end
