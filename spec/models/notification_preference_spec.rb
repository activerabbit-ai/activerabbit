require 'rails_helper'

RSpec.describe NotificationPreference, type: :model do
  let(:project) { create(:project) }
  let(:notification_preference) { create(:notification_preference, project: project) }

  describe "validations" do
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
  end
end
