class ApiToken < ApplicationRecord
  belongs_to :project

  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
  validates :token, length: { minimum: 32 }

  scope :active, -> { where(active: true) }

  before_validation :generate_token, if: -> { token.blank? }
  before_create :set_defaults

  def self.authenticate(token_value)
    return nil if token_value.blank?

    find_by(token: token_value, active: true)&.tap do |token|
      token.touch(:last_used_at)
      token.increment!(:usage_count)
    end
  end

  def mask_token
    return '[INVALID]' if token.blank?

    "#{token[0..7]}#{'*' * (token.length - 16)}#{token[-8..-1]}"
  end

  def revoke!
    update!(active: false, revoked_at: Time.current)
  end

  def activate!
    update!(active: true, revoked_at: nil)
  end

  def usage_stats
    {
      total_usage: usage_count,
      last_used: last_used_at,
      created: created_at,
      active: active?
    }
  end

  private

  def generate_token
    loop do
      self.token = SecureRandom.hex(32)
      break unless self.class.exists?(token: self.token)
    end
  end

  def set_defaults
    self.active = true if active.nil?
    self.usage_count = 0 if usage_count.nil?
  end
end
