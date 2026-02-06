require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  # Associations

  test "belongs to user optionally" do
    association = Project.reflect_on_association(:user)
    assert_equal :belongs_to, association.macro
    assert association.options[:optional]
  end

  test "has many issues with dependent destroy" do
    association = Project.reflect_on_association(:issues)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many events with dependent destroy" do
    association = Project.reflect_on_association(:events)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many perf_rollups with dependent destroy" do
    association = Project.reflect_on_association(:perf_rollups)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many releases with dependent destroy" do
    association = Project.reflect_on_association(:releases)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many api_tokens with dependent destroy" do
    association = Project.reflect_on_association(:api_tokens)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many healthchecks with dependent destroy" do
    association = Project.reflect_on_association(:healthchecks)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many alert_rules with dependent destroy" do
    association = Project.reflect_on_association(:alert_rules)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  # Validations

  test "validates presence of name" do
    project = Project.new(name: nil, environment: "production", url: "http://example.com", account: accounts(:default))
    refute project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "validates presence of environment" do
    project = Project.new(name: "Test", environment: nil, url: "http://example.com", account: accounts(:default))
    refute project.valid?
    assert_includes project.errors[:environment], "can't be blank"
  end

  test "validates presence of url" do
    project = Project.new(name: "Test", environment: "production", url: nil, account: accounts(:default))
    refute project.valid?
    assert_includes project.errors[:url], "can't be blank"
  end

  test "validates URL format" do
    project = Project.new(name: "Test", environment: "production", url: "not-a-url", account: accounts(:default))
    refute project.valid?

    project.url = "https://example.com"
    assert project.valid?
  end

  test "generates slug from name when slug is not provided" do
    project = Project.new(name: "My Test Project", environment: "production", url: "http://example.com", account: accounts(:default))
    project.valid?
    assert_equal "my-test-project", project.slug
  end

  test "is valid without a user" do
    project = Project.new(name: "Test", environment: "production", url: "http://example.com", account: accounts(:default), user: nil)
    # Need unique slug
    project.slug = "test-no-user-#{SecureRandom.hex(4)}"
    assert project.valid?
  end

  # generate_api_token!

  test "generate_api_token creates a token and returns it" do
    project = projects(:default)
    assert_difference -> { project.api_tokens.count }, 1 do
      project.generate_api_token!
    end
    assert project.api_token.present?
  end
end
