FactoryBot.define do
  factory :notification_preference do
    project { 1 }
    alert_type { "new_issue" }
    enabled { false }
    frequency { "immediate" }
    last_sent_at { "2025-12-16 20:14:48" }
  end
end
