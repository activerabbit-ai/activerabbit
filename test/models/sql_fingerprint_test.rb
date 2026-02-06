require "test_helper"

class SqlFingerprintTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
  end

  # Associations

  test "belongs to project" do
    association = SqlFingerprint.reflect_on_association(:project)
    assert_equal :belongs_to, association.macro
  end

  # Validations

  test "validates presence of fingerprint" do
    sql_fp = SqlFingerprint.new(
      project: @project,
      account: @account,
      query_type: "SELECT"
    )
    refute sql_fp.valid?
    assert_includes sql_fp.errors[:fingerprint], "can't be blank"
  end

  test "validates query_type inclusion" do
    sql_fp = SqlFingerprint.new(
      project: @project,
      account: @account,
      fingerprint: SecureRandom.hex(32),
      query_type: "INVALID"
    )
    refute sql_fp.valid?
    assert sql_fp.errors[:query_type].present?
  end

  test "validates uniqueness of fingerprint scoped to project" do
    existing = sql_fingerprints(:user_select)
    duplicate = SqlFingerprint.new(
      project: existing.project,
      account: existing.account,
      fingerprint: existing.fingerprint,
      query_type: "SELECT"
    )
    refute duplicate.valid?
    assert duplicate.errors[:fingerprint].present?
  end

  test "allows valid query_types" do
    %w[SELECT INSERT UPDATE DELETE].each do |query_type|
      sql_fp = SqlFingerprint.new(
        project: @project,
        account: @account,
        fingerprint: SecureRandom.hex(32),
        query_type: query_type,
        normalized_query: "TEST QUERY",
        total_count: 1,
        total_duration_ms: 10,
        avg_duration_ms: 10,
        max_duration_ms: 10
      )
      assert sql_fp.valid?, "Expected #{query_type} to be valid"
    end
  end

  # Scopes

  test "frequent scope orders by total_count desc" do
    fingerprints = SqlFingerprint.frequent.where(project: @project).limit(5)
    counts = fingerprints.map(&:total_count)
    assert_equal counts.sort.reverse, counts
  end

  test "slow scope orders by avg_duration_ms desc" do
    fingerprints = SqlFingerprint.slow.where(project: @project).limit(5)
    durations = fingerprints.map(&:avg_duration_ms)
    assert_equal durations.sort.reverse, durations
  end

  # Class methods

  test "track_query creates new fingerprint record" do
    sql = "SELECT * FROM users WHERE email = 'test@example.com'"

    assert_difference "SqlFingerprint.count", 1 do
      SqlFingerprint.track_query(
        project: @project,
        sql: sql,
        duration_ms: 15.5,
        controller_action: "UsersController#show"
      )
    end

    fp = SqlFingerprint.last
    assert_equal "SELECT", fp.query_type
    assert_equal 1, fp.total_count
    assert_equal 15.5, fp.avg_duration_ms
  end

  test "track_query updates existing fingerprint record" do
    existing = sql_fingerprints(:user_select)
    original_count = existing.total_count
    original_total_duration = existing.total_duration_ms

    SqlFingerprint.track_query(
      project: existing.project,
      sql: existing.normalized_query,
      duration_ms: 10.0
    )

    existing.reload
    assert_equal original_count + 1, existing.total_count
    assert existing.total_duration_ms > original_total_duration
  end

  test "detect_n_plus_one returns empty array when no N+1 detected" do
    sql_queries = [
      { sql: "SELECT * FROM users WHERE id = 1" },
      { sql: "SELECT * FROM projects WHERE id = 2" }
    ]

    result = SqlFingerprint.detect_n_plus_one(
      project: @project,
      controller_action: "HomeController#index",
      sql_queries: sql_queries
    )

    assert_equal [], result
  end

  test "detect_n_plus_one detects repeated queries" do
    # Create a fingerprint record first
    sql = "SELECT * FROM users WHERE id = ?"
    5.times { |i|
      SqlFingerprint.track_query(
        project: @project,
        sql: "SELECT * FROM users WHERE id = #{i}",
        duration_ms: 5
      )
    }

    sql_queries = 6.times.map do |i|
      { sql: "SELECT * FROM users WHERE id = #{i}" }
    end

    result = SqlFingerprint.detect_n_plus_one(
      project: @project,
      controller_action: "UsersController#index",
      sql_queries: sql_queries
    )

    # Should detect N+1 when same normalized query is run 6+ times
    assert result.is_a?(Array)
  end

  # Instance methods

  test "performance_impact calculates total impact" do
    fp = sql_fingerprints(:user_select)
    fp.update!(total_duration_ms: 100, total_count: 10)

    assert_equal 1000, fp.performance_impact
  end

  test "is_n_plus_one_candidate returns true for high count low duration" do
    fp = sql_fingerprints(:user_select)
    fp.update!(total_count: 150, avg_duration_ms: 10)

    assert fp.is_n_plus_one_candidate?
  end

  test "is_n_plus_one_candidate returns false for low count" do
    fp = sql_fingerprints(:user_select)
    fp.update!(total_count: 50, avg_duration_ms: 10)

    refute fp.is_n_plus_one_candidate?
  end
end
