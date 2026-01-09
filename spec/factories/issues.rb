FactoryBot.define do
  factory :issue do
    association :account
    association :project
    sequence(:fingerprint) { |n| Digest::SHA256.hexdigest("fp-#{n}") }
    exception_class { "RuntimeError" }
    top_frame { "/app/controllers/home_controller.rb:10:in `index'" }
    controller_action { "HomeController#index" }
    status { "open" }
    count { 1 }
    first_seen_at { Time.current }
    last_seen_at { Time.current }
    closed_at { nil }

    trait :closed do
      status { "closed" }
      closed_at { Time.current }
    end

    trait :wip do
      status { "wip" }
    end

    trait :record_not_found do
      exception_class { "ActiveRecord::RecordNotFound" }
    end
  end
end
