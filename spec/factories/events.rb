FactoryBot.define do
  factory :event do
    association :account
    association :project
    association :issue
    exception_class { "RuntimeError" }
    message { "Something went wrong" }
    backtrace { ["/app/controllers/home_controller.rb:10:in `index'"] }
    controller_action { "HomeController#index" }
    request_path { "/" }
    request_method { "GET" }
    occurred_at { Time.current }
    environment { "production" }
    context { {} }
  end
end
