class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  # Pay gem integration
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
      name: "#{email.split('@').first.humanize}'s Account"
    )
  end
end
