FactoryBot.define do
  factory :alert_notification do
    association :alert_rule
    association :project
    account { project.account }

    notification_type { "multi" }
    status { "pending" }
    payload { {} }

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      failed_at { Time.current }
      error_message { "Test error" }
    end

    trait :slack do
      notification_type { "slack" }
    end

    trait :email do
      notification_type { "email" }
    end
  end
end

