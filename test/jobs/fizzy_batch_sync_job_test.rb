require "test_helper"

class FizzyBatchSyncJobTest < ActiveSupport::TestCase
  setup do
    @project = projects(:default)
  end

  test "skips sync when not configured" do
    mock_service = OpenStruct.new(configured?: false)

    FizzySyncService.stub(:new, mock_service) do
      # Should return early without error
      assert_nothing_raised do
        FizzyBatchSyncJob.new.perform(@project.id)
      end
    end
  end

  test "skips sync when auto-sync not enabled and not forced" do
    mock_service = OpenStruct.new(
      configured?: true,
      sync_batch: { synced: 0, failed: 0 }
    )

    @project.stub(:fizzy_sync_enabled?, false) do
      FizzySyncService.stub(:new, mock_service) do
        assert_nothing_raised do
          FizzyBatchSyncJob.new.perform(@project.id, false)
        end
      end
    end
  end

  test "syncs when forced even if auto-sync disabled" do
    sync_called = false
    mock_service = Object.new

    def mock_service.configured?
      true
    end

    mock_service.define_singleton_method(:sync_batch) do |issues, force:|
      { synced: issues.count, failed: 0 }
    end

    FizzySyncService.stub(:new, mock_service) do
      # Should not raise when forced
      assert_nothing_raised do
        FizzyBatchSyncJob.new.perform(@project.id, true)
      end
    end
  end

  test "raises error when project not found" do
    assert_raises ActiveRecord::RecordNotFound do
      FizzyBatchSyncJob.new.perform(999999)
    end
  end

  test "syncs open issues for project" do
    synced_issues = nil
    mock_service = Object.new

    def mock_service.configured?
      true
    end

    def mock_service.sync_batch(issues, force:)
      @synced_issues = issues
      { synced: issues.count, failed: 0 }
    end

    Project.stub(:find, @project) do
      @project.stub(:fizzy_sync_enabled?, true) do
        FizzySyncService.stub(:new, mock_service) do
          assert_nothing_raised do
            FizzyBatchSyncJob.new.perform(@project.id)
          end
        end
      end
    end
  end
end
