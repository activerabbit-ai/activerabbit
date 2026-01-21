class Account < ApplicationRecord
  # Billing is managed per User (team unlock). Account holds entitlements.

  # Concerns
  include ResourceQuotas
  include QuotaWarnings

  # Validations
  validates :name, presence: true, uniqueness: true

  # Associations
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :api_tokens, through: :projects

  # Scopes
  scope :active, -> { where(active: true) }
  scope :with_expired_trial, -> { where("trial_ends_at < ?", Time.current) }
  scope :needing_payment_reminder, -> {
    with_expired_trial
      .where.not(current_plan: "free")
      .where("NOT EXISTS (
        SELECT 1 FROM pay_subscriptions ps
        JOIN pay_customers pc ON ps.customer_id = pc.id
        WHERE pc.owner_type = 'User'
        AND pc.owner_id IN (SELECT id FROM users WHERE account_id = accounts.id)
        AND ps.status = 'active'
      )")
  }

  # Billing helpers
  def on_trial?
    trial_ends_at.present? && Time.current < trial_ends_at
  end

  def trial_expired?
    trial_ends_at.present? && Time.current >= trial_ends_at
  end

  # Check if the account has a payment method on file via Stripe
  # Returns true if any user in the account has a valid payment method
  def has_payment_method?
    return @_has_payment_method if defined?(@_has_payment_method)

    @_has_payment_method = users.any? do |user|
      next false unless user.payment_processor&.processor_id.present?

      begin
        payment_methods = Stripe::PaymentMethod.list(
          customer: user.payment_processor.processor_id,
          type: "card"
        )
        payment_methods.data.any?
      rescue Stripe::InvalidRequestError => e
        Rails.logger.warn "Stripe error checking payment method for user #{user.id}: #{e.message}"
        false
      end
    end
  end

  # Check if account needs a payment method warning (during trial)
  def needs_payment_method_warning?
    on_trial? && !has_payment_method? && !active_subscription?
  end

  # Check if trial expired without payment method (account still gets Team plan but needs warning)
  def trial_expired_without_payment?
    trial_expired? && !has_payment_method? && !active_subscription?
  end

  # Check if account is in grace period (trial expired, no payment, but still providing Team access)
  def in_payment_grace_period?
    trial_expired_without_payment?
  end

  def active_subscription_record
    return @_active_subscription_record if defined?(@_active_subscription_record)

    user_ids_relation = users.select(:id)
    @_active_subscription_record = Pay::Subscription
                                    .joins(:customer)
                                    .where(status: "active")
                                    .where(pay_customers: { owner_type: "User", owner_id: user_ids_relation })
                                    .order(updated_at: :desc)
                                    .first
  end

  def active_subscription?
    active_subscription_record.present?
  end

  # Account-wide Slack notification settings
  def slack_webhook_url
    # Priority: ENV variable > account setting
    env_webhook = ENV["SLACK_WEBHOOK_URL_#{name.parameterize.upcase}"] || ENV["SLACK_WEBHOOK_URL"]
    env_webhook.presence || settings&.dig("slack_webhook_url")
  end

  def slack_webhook_url=(url)
    # Only store in database if not using environment variable
    if url.present? && !url.start_with?("ENV:")
      self.settings = (settings || {}).merge("slack_webhook_url" => url&.strip)
    elsif url&.start_with?("ENV:")
      # Store reference to environment variable
      env_var = url.sub("ENV:", "")
      self.settings = (settings || {}).merge("slack_webhook_url" => "ENV:#{env_var}")
    else
      # Clear the setting
      new_settings = (settings || {}).dup
      new_settings.delete("slack_webhook_url")
      self.settings = new_settings
    end
  end

  def slack_channel
    settings&.dig("slack_channel") || "#alerts"
  end

  def slack_channel=(channel)
    # Ensure channel starts with # if it's not a user DM
    formatted_channel = channel&.strip
    if formatted_channel.present? && !formatted_channel.start_with?("#", "@")
      formatted_channel = "##{formatted_channel}"
    end
    self.settings = (settings || {}).merge("slack_channel" => formatted_channel)
  end

  def slack_configured?
    settings&.dig("slack_webhook_url").present?
  end

  def slack_notifications_enabled?
    slack_configured? && settings&.dig("slack_notifications_enabled") != false
  end

  def enable_slack_notifications!
    self.settings = (settings || {}).merge("slack_notifications_enabled" => true)
    save!
  end

  def disable_slack_notifications!
    self.settings = (settings || {}).merge("slack_notifications_enabled" => false)
    save!
  end

  def slack_webhook_from_env?
    settings&.dig("slack_webhook_url")&.start_with?("ENV:") ||
    ENV["SLACK_WEBHOOK_URL_#{name.parameterize.upcase}"].present? ||
    ENV["SLACK_WEBHOOK_URL"].present?
  end

  # User notification preferences within this account
  def user_notification_preferences(user)
    settings&.dig("user_preferences", user.id.to_s) || default_user_preferences
  end

  def update_user_notification_preferences(user, preferences)
    current_settings = settings || {}
    current_settings["user_preferences"] ||= {}
    current_settings["user_preferences"][user.id.to_s] = preferences
    update!(settings: current_settings)
  end

  def to_s
    name
  end

  private

  def default_user_preferences
    {
      "error_notifications" => true,
      "performance_notifications" => true,
      "n_plus_one_notifications" => true,
      "new_issue_notifications" => true,
      "personal_channel" => nil # nil means use account default channel
    }
  end
end
