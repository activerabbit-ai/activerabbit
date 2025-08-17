class SqlFingerprint < ApplicationRecord
  belongs_to :project

  validates :fingerprint, presence: true, uniqueness: { scope: :project_id }
  validates :query_type, inclusion: { in: %w[SELECT INSERT UPDATE DELETE] }

  scope :frequent, -> { order(total_count: :desc) }
  scope :slow, -> { order(avg_duration_ms: :desc) }
  scope :n_plus_one_candidates, -> { where('total_count > ? AND avg_duration_ms < ?', 100, 50) }

  def self.track_query(project:, sql:, duration_ms:, controller_action: nil)
    fingerprint = generate_fingerprint(sql)
    query_type = extract_query_type(sql)

    sql_fingerprint = find_or_initialize_by(
      project: project,
      fingerprint: fingerprint
    )

    if sql_fingerprint.persisted?
      # Update existing record
      new_count = sql_fingerprint.total_count + 1
      new_total_duration = sql_fingerprint.total_duration_ms + duration_ms

      sql_fingerprint.update!(
        total_count: new_count,
        total_duration_ms: new_total_duration,
        avg_duration_ms: new_total_duration.to_f / new_count,
        max_duration_ms: [sql_fingerprint.max_duration_ms, duration_ms].max,
        last_seen_at: Time.current
      )
    else
      # Create new record
      sql_fingerprint.assign_attributes(
        query_type: query_type,
        normalized_query: normalize_query(sql),
        total_count: 1,
        total_duration_ms: duration_ms,
        avg_duration_ms: duration_ms,
        max_duration_ms: duration_ms,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        controller_action: controller_action
      )
      sql_fingerprint.save!
    end

    sql_fingerprint
  end

  def self.detect_n_plus_one(project:, controller_action:, sql_queries:)
    return [] if sql_queries.empty?

    # Group queries by fingerprint
    query_counts = Hash.new(0)
    sql_queries.each do |query|
      fingerprint = generate_fingerprint(query[:sql])
      query_counts[fingerprint] += 1
    end

    # Find queries executed more than threshold times
    n_plus_one_threshold = 5
    suspicious_fingerprints = query_counts.select { |_, count| count >= n_plus_one_threshold }

    return [] if suspicious_fingerprints.empty?

    # Get SQL fingerprint records for analysis
    fingerprints = where(
      project: project,
      fingerprint: suspicious_fingerprints.keys
    )

    n_plus_one_incidents = []
    fingerprints.each do |fp|
      count_in_request = query_counts[fp.fingerprint]

      n_plus_one_incidents << {
        sql_fingerprint: fp,
        count_in_request: count_in_request,
        controller_action: controller_action,
        severity: calculate_severity(count_in_request, fp.avg_duration_ms),
        suggestion: generate_suggestion(fp)
      }
    end

    n_plus_one_incidents
  end

  def performance_impact
    total_duration_ms * total_count
  end

  def is_n_plus_one_candidate?
    total_count > 100 && avg_duration_ms < 50
  end

  private

  def self.generate_fingerprint(sql)
    normalized = normalize_query(sql)
    Digest::SHA256.hexdigest(normalized)
  end

  def self.normalize_query(sql)
    # Remove specific values and normalize query structure
    normalized = sql.dup

    # Replace string literals
    normalized.gsub!(/'[^']*'/, "'?'")

    # Replace numeric literals
    normalized.gsub(/\b\d+\b/, '?')

    # Replace IN clauses with multiple values
    normalized.gsub(/IN\s*\([^)]+\)/i, 'IN (?)')

    # Replace LIMIT/OFFSET values
    normalized.gsub(/LIMIT\s+\d+/i, 'LIMIT ?')
    normalized.gsub(/OFFSET\s+\d+/i, 'OFFSET ?')

    # Normalize whitespace
    normalized.gsub(/\s+/, ' ').strip.upcase
  end

  def self.extract_query_type(sql)
    case sql.strip.upcase
    when /^SELECT/
      'SELECT'
    when /^INSERT/
      'INSERT'
    when /^UPDATE/
      'UPDATE'
    when /^DELETE/
      'DELETE'
    else
      'OTHER'
    end
  end

  def self.calculate_severity(count, avg_duration)
    impact_score = count * avg_duration

    case impact_score
    when 0..100
      'low'
    when 101..500
      'medium'
    else
      'high'
    end
  end

  def self.generate_suggestion(sql_fingerprint)
    query = sql_fingerprint.normalized_query

    if query.include?('SELECT') && query.include?('WHERE')
      if query.include?('users.id = ?')
        "Consider using includes(:user) or joins(:user) to avoid N+1 queries"
      elsif query.match?(/\w+\.id = \?/)
        "Consider eager loading this association to reduce database queries"
      else
        "Review if this query can be optimized with proper indexing or eager loading"
      end
    else
      "Review query performance and consider optimization"
    end
  end
end
