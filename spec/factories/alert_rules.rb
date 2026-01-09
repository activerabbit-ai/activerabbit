FactoryBot.define do
  factory :alert_rule do
    association :project
    account { project.account }

    sequence(:name) { |n| "Alert Rule #{n}" }
    rule_type { "new_issue" }
    threshold_value { 1 }
    time_window_minutes { 5 }
    cooldown_minutes { 30 }
    enabled { true }

    trait :error_frequency do
      rule_type { "error_frequency" }
      threshold_value { 10 }
      time_window_minutes { 5 }
    end

    trait :performance_regression do
      rule_type { "performance_regression" }
      threshold_value { 2000 }
      time_window_minutes { 1 }
      cooldown_minutes { 15 }
    end

    trait :n_plus_one do
      rule_type { "n_plus_one" }
      threshold_value { 1 }
      time_window_minutes { 1 }
      cooldown_minutes { 60 }
    end

    trait :disabled do
      enabled { false }
    end
  end
end

