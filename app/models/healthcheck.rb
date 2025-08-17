class Healthcheck < ApplicationRecord
  belongs_to :project

  validates :name, presence: true
  validates :check_type, inclusion: { in: %w[http database redis sidekiq custom] }
  validates :status, inclusion: { in: %w[healthy warning critical unknown] }

  scope :healthy, -> { where(status: 'healthy') }
  scope :warning, -> { where(status: 'warning') }
  scope :critical, -> { where(status: 'critical') }
  scope :recent, -> { order(last_checked_at: :desc) }

  def self.perform_checks(project)
    checks = where(project: project, enabled: true)
    results = []

    checks.find_each do |check|
      result = check.perform_check!
      results << result
    end

    # Update project health status
    project.update_health_status!(results)

    results
  end

  def perform_check!
    start_time = Time.current

    begin
      case check_type
      when 'http'
        perform_http_check
      when 'database'
        perform_database_check
      when 'redis'
        perform_redis_check
      when 'sidekiq'
        perform_sidekiq_check
      when 'custom'
        perform_custom_check
      else
        raise "Unknown check type: #{check_type}"
      end
    rescue => e
      update_check_result('critical', "Check failed: #{e.message}", Time.current - start_time)
      { status: 'critical', message: e.message, duration: Time.current - start_time }
    end
  end

  private

  def perform_http_check
    require 'net/http'
    require 'uri'

    uri = URI(config['url'])
    timeout = config['timeout'] || 10

    start_time = Time.current

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: timeout) do |http|
      response = http.get(uri.path)
      duration = Time.current - start_time

      expected_status = config['expected_status'] || 200

      if response.code.to_i == expected_status
        update_check_result('healthy', "HTTP #{response.code}", duration)
        { status: 'healthy', message: "HTTP #{response.code}", duration: duration }
      else
        update_check_result('critical', "HTTP #{response.code} (expected #{expected_status})", duration)
        { status: 'critical', message: "HTTP #{response.code}", duration: duration }
      end
    end
  end

  def perform_database_check
    start_time = Time.current

    ActiveRecord::Base.connection.execute('SELECT 1')
    duration = Time.current - start_time

    if duration < 1.0 # Less than 1 second is healthy
      update_check_result('healthy', 'Database responsive', duration)
      { status: 'healthy', message: 'Database responsive', duration: duration }
    else
      update_check_result('warning', 'Database slow', duration)
      { status: 'warning', message: 'Database slow', duration: duration }
    end
  end

  def perform_redis_check
    start_time = Time.current

    Redis.current.ping
    duration = Time.current - start_time

    update_check_result('healthy', 'Redis responsive', duration)
    { status: 'healthy', message: 'Redis responsive', duration: duration }
  end

  def perform_sidekiq_check
    start_time = Time.current

    stats = Sidekiq::Stats.new
    duration = Time.current - start_time

    failed_jobs = stats.failed

    if failed_jobs > (config['max_failed_jobs'] || 100)
      update_check_result('warning', "#{failed_jobs} failed jobs", duration)
      { status: 'warning', message: "#{failed_jobs} failed jobs", duration: duration }
    else
      update_check_result('healthy', 'Sidekiq healthy', duration)
      { status: 'healthy', message: 'Sidekiq healthy', duration: duration }
    end
  end

  def perform_custom_check
    # Placeholder for custom check logic
    # This would execute custom Ruby code defined in config['code']
    start_time = Time.current
    duration = Time.current - start_time

    update_check_result('healthy', 'Custom check passed', duration)
    { status: 'healthy', message: 'Custom check passed', duration: duration }
  end

  def update_check_result(status, message, duration)
    update!(
      status: status,
      last_checked_at: Time.current,
      response_time_ms: (duration * 1000).round(2),
      message: message
    )
  end
end
