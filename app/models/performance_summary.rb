class PerformanceSummary < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project

  validates :target, presence: true
  validates :summary, presence: true

  scope :for_target, ->(target) { where(target: target) }
end
