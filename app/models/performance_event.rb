class PerformanceEvent < ApplicationRecord
  # Multi-tenancy setup - PerformanceEvent belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project
  belongs_to :release, optional: true

  validates :occurred_at, presence: true
  validates :duration_ms, presence: true, numericality: { greater_than: 0 }
  validates :target, presence: true  # controller#action or job class

  scope :recent, -> { order(occurred_at: :desc) }
  scope :for_timerange, ->(start_time, end_time) { where(occurred_at: start_time..end_time) }
  scope :for_target, ->(target) { where(target: target) }
  scope :slow, -> { where("duration_ms > ?", 1000) } # > 1 second
  scope :within_retention, ->(cutoff) { where("occurred_at >= ?", cutoff) }

  before_create :set_defaults

  def self.ingest_performance(project:, payload:)
    target = payload[:controller_action] || payload[:job_class] || "unknown"

    # Only store positive values, use NULL for zeros (more efficient storage and queries)
    db_ms = payload[:db_duration_ms].to_f
    view_ms = payload[:view_duration_ms].to_f
    allocs = payload[:allocations].to_i
    sql_count = payload[:sql_queries_count].to_i

    create!(
      project: project,
      target: target,
      duration_ms: payload[:duration_ms],
      db_duration_ms: db_ms > 0 ? db_ms : nil,
      view_duration_ms: view_ms > 0 ? view_ms : nil,
      allocations: allocs > 0 ? allocs : nil,
      sql_queries_count: sql_count > 0 ? sql_count : nil,
      occurred_at: payload[:occurred_at] || Time.current,
      environment: payload[:environment] || "production",
      release_version: payload[:release_version],
      request_path: payload[:request_path],
      request_method: payload[:request_method],
      user_id_hash: payload[:user_id] ? Digest::SHA256.hexdigest(payload[:user_id].to_s) : nil,
      context: Event.scrub_pii(payload[:context] || {}),
      server_name: payload[:server_name],
      request_id: payload[:request_id]
    )
  end

  def slow?
    duration_ms > 1000
  end

  def very_slow?
    duration_ms > 5000
  end

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.environment ||= "production"
  end
end
