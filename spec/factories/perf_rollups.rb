FactoryBot.define do
  factory :perf_rollup do
    association :account
    association :project
    timeframe { "minute" }
    timestamp { Time.current.change(sec: 0) }
    target { "HomeController#index" }
    environment { "production" }
    request_count { 10 }
    avg_duration_ms { 300.0 }
    p50_duration_ms { 250.0 }
    p95_duration_ms { 1200.0 }
    p99_duration_ms { 1800.0 }
    min_duration_ms { 100.0 }
    max_duration_ms { 5000.0 }
    error_count { 0 }
  end
end


