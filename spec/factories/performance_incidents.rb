FactoryBot.define do
  factory :performance_incident do
    association :project
    account { project.account }

    target { "UsersController#index" }
    status { "open" }
    severity { "warning" }
    opened_at { Time.current }
    trigger_p95_ms { 850.0 }
    peak_p95_ms { 900.0 }
    threshold_ms { 750.0 }
    breach_count { 3 }
    environment { "production" }
    open_notification_sent { false }
    close_notification_sent { false }

    trait :warning do
      severity { "warning" }
      trigger_p95_ms { 850.0 }
      threshold_ms { 750.0 }
    end

    trait :critical do
      severity { "critical" }
      trigger_p95_ms { 1800.0 }
      threshold_ms { 1500.0 }
    end

    trait :closed do
      status { "closed" }
      closed_at { 10.minutes.from_now }
      resolve_p95_ms { 400.0 }
      close_notification_sent { true }
    end

    trait :open do
      status { "open" }
      closed_at { nil }
      resolve_p95_ms { nil }
    end

    trait :notified do
      open_notification_sent { true }
    end
  end
end

