FactoryBot.define do
  factory :notification_preference do
    association :project
    alert_type { "new_issue" }
    enabled { true }
    frequency { "every_2_hours" }
    last_sent_at { nil }
  end
end
