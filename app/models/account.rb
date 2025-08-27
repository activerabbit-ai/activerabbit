class Account < ApplicationRecord
  # Validations
  validates :name, presence: true, uniqueness: true

  # Associations
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :api_tokens, through: :projects

  # Scopes
  scope :active, -> { where(active: true) }

  def to_s
    name
  end
end
