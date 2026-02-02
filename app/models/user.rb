class User < ApplicationRecord
  ROLES = %w[owner member].freeze
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
  # Don't destroy projects when user is deleted - they belong to the account
  has_many :projects, dependent: :nullify
  belongs_to :invited_by, class_name: "User", optional: true

  # Avatar
  has_one_attached :avatar

  # Validations
  validates :role, inclusion: { in: ROLES }

  # Avatar validation
  validate :avatar_validation

  # Callbacks - Create account BEFORE user creation
  before_validation :ensure_account_exists, on: :create

  before_validation :assign_default_owner_role, on: :create

  def needs_onboarding?
    return true if account.blank?

    # Use without_tenant to bypass scoping issues during sign-in
    # when the tenant may not be set yet
    ActsAsTenant.without_tenant do
      !account.projects.exists?
    end
  end

  def self.from_omniauth(auth)
    # Get email from auth.info first, fallback to verified emails from GitHub API
    auth_email = auth.info.email.presence || extract_email_from_github(auth)

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

  # Extract primary verified email from GitHub OAuth response
  # GitHub returns emails in auth.extra.all_emails when user:email scope is requested
  def self.extract_email_from_github(auth)
    return nil unless auth.provider == "github"

    emails = auth.extra&.all_emails || auth.extra&.raw_info&.emails
    return nil if emails.blank?

    # Helper to access hash with string or symbol keys
    get_value = ->(hash, key) { hash[key.to_s] || hash[key.to_sym] }

    # Prefer primary + verified, then any verified, then first available
    primary = emails.find { |e| get_value.call(e, :primary) && get_value.call(e, :verified) }
    return get_value.call(primary, :email) if primary

    verified = emails.find { |e| get_value.call(e, :verified) }
    return get_value.call(verified, :email) if verified

    get_value.call(emails.first, :email)
  end

  def owner?
    role == "owner"
  end

  def member?
    role == "member"
  end

  def super_admin?
    super_admin == true
  end

  def password_required?
    if invited_by.present?
      false
    else
      super
    end
  end

  def avatar_variant(size: 128)
    return unless avatar.attached?

    avatar.variant(
      resize_to_fill: [size, size],
      saver: { strip: true }
    )
  end

  private

  def ensure_account_exists
    return if account.present?

    base_name =
      if email.present?
        "#{email.split('@').first.humanize}'s Account"
      else
        "New Account #{SecureRandom.hex(4)}"
      end

    self.account = Account.find_or_create_by!(
      name: base_name
    ) do |a|
      a.trial_ends_at = Rails.configuration.x.trial_days.days.from_now
      a.current_plan = "team"
      a.billing_interval = "month"
      a.event_quota = 100_000
      a.events_used_in_period = 0
    end
  end

  def assign_default_owner_role
    if invited_by.nil?
      self.role = "owner" if role.blank?
    else
      self.role = role.presence || "member"
    end
  end

  def avatar_validation
    return unless avatar.attached?

    if avatar.blob.byte_size > 5.megabytes
      errors.add(:avatar, "is too large (max 5MB)")
    end

    allowed = %w[image/jpeg image/png image/webp]
    unless avatar.blob.content_type.in?(allowed)
      errors.add(:avatar, "must be JPG/PNG/WebP")
    end
  end
end
