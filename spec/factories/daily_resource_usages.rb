# frozen_string_literal: true

FactoryBot.define do
  factory :daily_resource_usage do
    association :account
    day { Date.current }
    errors_count { 100 }
    ai_summaries_count { 10 }
    pull_requests_count { 5 }
    uptime_monitors_count { 3 }
    status_pages_count { 1 }

    trait :with_no_usage do
      errors_count { nil }
      ai_summaries_count { nil }
      pull_requests_count { nil }
      uptime_monitors_count { nil }
      status_pages_count { nil }
    end

    trait :with_high_usage do
      errors_count { 45_000 }
      ai_summaries_count { 95 }
      pull_requests_count { 18 }
      uptime_monitors_count { 5 }
      status_pages_count { 1 }
    end

    trait :yesterday do
      day { Date.yesterday }
    end

    trait :last_week do
      day { 1.week.ago.to_date }
    end
  end
end
