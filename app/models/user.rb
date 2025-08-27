class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  # Pay gem integration
  pay_customer

  # Multi-tenancy: User belongs to Account
  belongs_to :account, optional: true

  # ActiveRabbit relationships (scoped to account through acts_as_tenant)
  has_many :projects, dependent: :destroy

  # Validations
  validates :account_id, presence: true, on: :update
  # Don't validate account_id presence on create - it will be set by callback

  # Callbacks
  after_create :create_account_and_project!, if: -> { account_id.blank? }

  def create_default_project!
    projects.create!(
      name: "Default Project",
      environment: "production",
      description: "Default project for #{email}"
    ).tap do |project|
      project.generate_api_token!
      project.create_default_alert_rules!
    end
  end

  def create_account_and_project!
    # Create account for new user
    account = Account.create!(name: "#{email.split('@').first.humanize}'s Account")

    # Update account_id without triggering validations
    update_column(:account_id, account.id)

    # Reload to get the association
    reload

    # Create default project
    create_default_project!
  end
end
