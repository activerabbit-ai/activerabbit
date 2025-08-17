class Issue < ApplicationRecord
  belongs_to :project
  has_many :events, dependent: :destroy

  validates :fingerprint, presence: true, uniqueness: { scope: :project_id }
  validates :exception_type, presence: true
  validates :message, presence: true
  validates :status, inclusion: { in: %w[open resolved ignored] }

  scope :open, -> { where(status: 'open') }
  scope :resolved, -> { where(status: 'resolved') }
  scope :ignored, -> { where(status: 'ignored') }
  scope :recent, -> { order(last_seen_at: :desc) }

  def self.find_or_create_by_fingerprint(project:, fingerprint:, attributes: {})
    issue = find_by(project: project, fingerprint: fingerprint)

    if issue
      issue.update!(
        count: issue.count + 1,
        last_seen_at: Time.current,
        status: 'open' # Reopen if it was resolved
      )
    else
      issue = create!(
        project: project,
        fingerprint: fingerprint,
        count: 1,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        status: 'open',
        **attributes
      )
    end

    issue
  end

  def resolve!
    update!(status: 'resolved', resolved_at: Time.current)
  end

  def ignore!
    update!(status: 'ignored')
  end

  def reopen!
    update!(status: 'open', resolved_at: nil)
  end

  def title
    "#{exception_type}: #{message.truncate(100)}"
  end
end
