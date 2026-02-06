require "test_helper"

class DeployTest < ActiveSupport::TestCase
  test "deploy belongs to project" do
    deploy = deploys(:default)
    assert deploy.project.present?
  end

  test "deploy belongs to release" do
    deploy = deploys(:default)
    assert deploy.release.present?
  end

  test "deploy belongs to account" do
    deploy = deploys(:default)
    assert deploy.account.present?
  end
end
