FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    confirmed_at { Time.current } # Default to confirmed

    trait :super_admin do
      super_admin { true }
    end

    trait :owner do
      role { "owner" }
    end

    trait :member do
      role { "member" }
    end

    trait :confirmed do
      confirmed_at { Time.current }
    end

    trait :unconfirmed do
      confirmed_at { nil }
      provider { nil }
    end

    trait :oauth do
      provider { "github" }
      uid { SecureRandom.hex(10) }
      confirmed_at { nil } # OAuth users don't need confirmed_at
    end
  end
end
