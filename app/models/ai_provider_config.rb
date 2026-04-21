class AiProviderConfig < ApplicationRecord
  belongs_to :account

  encrypts :api_key

  validates :provider, presence: true
  validates :api_key, presence: true

  scope :active, -> { where(active: true) }

  def activate!
    transaction do
      account.ai_provider_configs.where.not(id: id).update_all(active: false)
      update!(active: true)
    end
  end
end
