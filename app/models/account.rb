class Account < ApplicationRecord
  # Billing is managed per User (team unlock). Account holds entitlements.
  # Validations
  validates :name, presence: true, uniqueness: true

  # Associations
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :api_tokens, through: :projects

  # Scopes
  scope :active, -> { where(active: true) }

  # Billing helpers
  def on_trial?
    trial_ends_at.present? && Time.current < trial_ends_at
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

  def event_quota_value
    return event_quota if respond_to?(:event_quota) && event_quota.present?
    case current_plan
    when "team" then 100_000
    else 50_000
    end
  end

  def events_used_in_billing_period
    start_at = event_usage_period_start || Time.current.beginning_of_month
    end_at   = event_usage_period_end || Time.current.end_of_month
    Event.where(account_id: id).where(occurred_at: start_at..end_at).count
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
    slack_webhook_url.present?
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
