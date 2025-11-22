class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :omniauthable, omniauth_providers: %i[github google_oauth2]

  # Billing handled per User (one Stripe customer per user)
  pay_customer

  # Multi-tenancy: User belongs to Account (required)
  belongs_to :account
  delegate :active_subscription_record, :active_subscription?, to: :account

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

  def self.from_omniauth(auth)
    auth_email = auth.info.email

    user = find_by(provider: auth.provider, uid: auth.uid)

    if user.nil? && auth_email.present?
      user = find_by(email: auth_email)

      if user.present?
        user.update_columns(provider: auth.provider, uid: auth.uid)
        return user
      end
    end

    user || find_or_initialize_by(provider: auth.provider, uid: auth.uid) do |new_user|
      new_user.email = auth_email
      new_user.password = SecureRandom.hex(20)
      new_user.name = auth.info.name if new_user.respond_to?(:name)

      new_user.save
    end
  end

  private

  def ensure_account_exists
    return if account.present?

    self.account = Account.find_or_create_by!(
      name: "#{email.split('@').first.humanize}'s Account"
    ) do |a|
      a.trial_ends_at = Rails.configuration.x.trial_days.days.from_now
      a.current_plan = "team"
      a.billing_interval = "month"
      a.event_quota = 100_000
      a.events_used_in_period = 0
    end
  end
end
