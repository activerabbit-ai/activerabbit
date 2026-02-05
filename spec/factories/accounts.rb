FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    active { true }

    trait :with_stats do
      cached_events_used { 100 }
      cached_performance_events_used { 50 }
      usage_cached_at { Time.current }
    end

    trait :without_stats do
      cached_events_used { 0 }
      cached_performance_events_used { 0 }
      cached_ai_summaries_used { 0 }
      cached_pull_requests_used { 0 }
      usage_cached_at { Time.current }
    end

    trait :free_plan do
      current_plan { "free" }
      trial_ends_at { 1.day.ago } # Trial expired
    end

    trait :team_plan do
      current_plan { "team" }
    end

    trait :on_trial do
      current_plan { "team" }
      trial_ends_at { 7.days.from_now }
    end
  end
end
