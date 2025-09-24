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
  end
end


