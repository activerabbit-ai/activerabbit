class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  # Billing handled per User (one Stripe customer per user)
  pay_customer

  # Multi-tenancy: User belongs to Account (required)
  belongs_to :account

  # ActiveRabbit relationships (scoped to account through acts_as_tenant)
  has_many :projects, dependent: :destroy

  # Callbacks - Create account BEFORE user creation
  before_validation :ensure_account_exists, on: :create

  def needs_onboarding?
    # Handle case when no tenant is set (during registration)
    return true if account.blank?

    # Use direct database query to avoid acts_as_tenant scoping issues
    Project.where(user_id: id).count == 0
  end

  private

  def ensure_account_exists
    return if account.present?

    # Create account before user validation/creation
    self.account = Account.create!(
      name: "#{email.split('@').first.humanize}'s Account",
      trial_ends_at: Rails.configuration.x.trial_days.days.from_now,
      current_plan: "team",
      billing_interval: "month",
      event_quota: 100_000,
      events_used_in_period: 0
    )
  end
end
