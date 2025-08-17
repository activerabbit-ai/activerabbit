class Issue < ApplicationRecord
  belongs_to :project
  has_many :events, dependent: :destroy

  validates :fingerprint, presence: true, uniqueness: { scope: :project_id }
  validates :exception_class, presence: true
  validates :top_frame, presence: true
  validates :controller_action, presence: true
  validates :status, inclusion: { in: %w[open wip closed] }

  scope :open, -> { where(status: 'open') }
  scope :wip, -> { where(status: 'wip') }
  scope :closed, -> { where(status: 'closed') }
  scope :recent, -> { order(last_seen_at: :desc) }
  scope :by_frequency, -> { order(count: :desc) }

  def self.find_or_create_by_fingerprint(project:, exception_class:, top_frame:, controller_action:, sample_message: nil)
    # Create fingerprint from exception class + top frame + controller action
    fingerprint = generate_fingerprint(exception_class, top_frame, controller_action)

    issue = find_by(project: project, fingerprint: fingerprint)

    if issue
      # Auto-reopen if closed
      if issue.status == 'closed'
        issue.update!(
          status: 'open',
          closed_at: nil,
          count: issue.count + 1,
          last_seen_at: Time.current
        )
      else
        issue.update!(
          count: issue.count + 1,
          last_seen_at: Time.current
        )
      end
    else
      # Create new issue
      issue = create!(
        project: project,
        fingerprint: fingerprint,
        exception_class: exception_class,
        top_frame: top_frame,
        controller_action: controller_action,
        sample_message: sample_message,
        count: 1,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        status: 'open'
      )
    end

    issue
  end

  def mark_wip!
    update!(status: 'wip')
  end

  def close!
    update!(status: 'closed', closed_at: Time.current)
  end

  def reopen!
    update!(status: 'open', closed_at: nil)
  end

  def title
    "#{exception_class} in #{controller_action}"
  end

  def source_location
    "#{controller_action} (#{top_frame})"
  end

  def events_last_24h
    events.where('created_at > ?', 24.hours.ago).count
  end

  private

  def self.generate_fingerprint(exception_class, top_frame, controller_action)
    # Normalize top frame (remove line numbers, normalize paths)
    normalized_frame = top_frame.gsub(/:\d+/, ':N').gsub(/\/\d+\//, '/N/')

    components = [
      exception_class,
      normalized_frame,
      controller_action
    ].compact

    Digest::SHA256.hexdigest(components.join('|'))
  end
end
