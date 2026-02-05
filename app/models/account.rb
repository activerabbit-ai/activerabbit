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
  #
  # Performance optimizations:
  # - Results are cached for 5 minutes to avoid repeated Stripe API calls
  # - Only checks users with Stripe customer IDs
  # - Stops at first user with a payment method
  # - Uses limit: 1 on Stripe API to minimize response time
  # - 3 second timeout to prevent page hangs
  def has_payment_method?
    return @_has_payment_method if defined?(@_has_payment_method)

    # Skip Stripe API call if no API key is configured
    unless Stripe.api_key.present? || ENV["STRIPE_SECRET_KEY"].present?
      @_has_payment_method = false
      return @_has_payment_method
    end

    # Check cache first (5 minute TTL)
    cache_key = "account:#{id}:has_payment_method"
    cached_result = Rails.cache.read(cache_key)
    if cached_result != nil
      @_has_payment_method = cached_result
      return @_has_payment_method
    end

    # Wrap in timeout to prevent page hangs if Stripe is slow
    result = Timeout.timeout(3) do
      check_stripe_payment_methods
    end

    # Cache the result for 5 minutes
    Rails.cache.write(cache_key, result, expires_in: 5.minutes)
    @_has_payment_method = result
  rescue Timeout::Error
    Rails.logger.warn "[Account#has_payment_method?] Stripe API timeout for account #{id}"
    # Don't cache timeout - try again next request
    @_has_payment_method = false
  end

  # Check if account needs a payment method warning (during trial)
  # Memoized since it's called multiple times per request (view + banner)
  def needs_payment_method_warning?
    return @_needs_payment_method_warning if defined?(@_needs_payment_method_warning)
    @_needs_payment_method_warning = on_trial? && !has_payment_method? && !active_subscription?
  end

  # Check if trial expired without payment method (account still gets Team plan but needs warning)
  # Memoized since it's called multiple times per request (view + banner)
  def trial_expired_without_payment?
    return @_trial_expired_without_payment if defined?(@_trial_expired_without_payment)
    @_trial_expired_without_payment = trial_expired? && !has_payment_method? && !active_subscription?
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

  # Check if the account has any usage stats (events, performance events, etc.)
  # Used to skip sending reports to accounts with no data
  def has_any_stats?
    return false unless usage_data_available?

    cached_events_used.to_i > 0 ||
      cached_performance_events_used.to_i > 0 ||
      cached_ai_summaries_used.to_i > 0 ||
      cached_pull_requests_used.to_i > 0
  end

  private

  def check_stripe_payment_methods
    # Ensure API key is set
    Stripe.api_key ||= ENV["STRIPE_SECRET_KEY"]

    # Only load users that have a Stripe customer - use a single efficient query
    # This avoids N+1 and only checks users who could have payment methods
    users_with_stripe = users
      .joins("INNER JOIN pay_customers ON pay_customers.owner_id = users.id AND pay_customers.owner_type = 'User'")
      .where.not(pay_customers: { processor_id: [nil, ""] })
      .select("users.id, pay_customers.processor_id AS stripe_customer_id")
      .limit(5) # Only check first 5 users max - if one has payment, we're done

    users_with_stripe.any? do |user_data|
      begin
        # Use limit: 1 to minimize Stripe API response time
        payment_methods = Stripe::PaymentMethod.list(
          customer: user_data.stripe_customer_id,
          type: "card",
          limit: 1
        )
        payment_methods.data.any?
      rescue Stripe::StripeError => e
        Rails.logger.warn "Stripe error checking payment method for customer #{user_data.stripe_customer_id}: #{e.message}"
        false
      end
    end
  end

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
