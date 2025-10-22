FactoryBot.define do
  factory :performance_event do
    association :account
    association :project
    target { "HomeController#index" }
    duration_ms { 250.0 }
    db_duration_ms { 80.0 }
    view_duration_ms { 120.0 }
    allocations { 12000 }
    sql_queries_count { 12 }
    occurred_at { Time.current }
    environment { "production" }
    context { {} }
  end
end



