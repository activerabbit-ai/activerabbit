# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Issues::FingerprintRecomputer, type: :service do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }

  before do
    ActsAsTenant.current_tenant = account
    # Clean up all issues before each test since FingerprintRecomputer processes ALL issues
    # Must use without_tenant because the service bypasses tenant scoping
    # Delete events first due to foreign key constraint
    ActsAsTenant.without_tenant do
      Event.delete_all
      Issue.delete_all
    end
  end

  describe '#call' do
    context 'when issues have old-style fingerprints (by controller action)' do
      # Simulate old fingerprinting: exception_class + controller_action (ignoring top_frame)
      def old_style_fingerprint(exception_class, controller_action)
        Digest::SHA256.hexdigest([exception_class, controller_action].join("|"))
      end

      it 'merges RecordNotFound issues from same origin into one' do
        # Create 3 issues with OLD fingerprints (as if they were created before the change)
        # All have same origin (base_controller.rb:214) but different controllers
        issue1 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/reports/base_controller.rb:214',
          controller_action: 'Reports::HoursController#index',
          fingerprint: old_style_fingerprint('ActiveRecord::RecordNotFound', 'Reports::HoursController#index'),
          count: 10,
          first_seen_at: 3.days.ago,
          last_seen_at: 1.day.ago
        )

        issue2 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/reports/base_controller.rb:214',
          controller_action: 'Reports::TasksController#index',
          fingerprint: old_style_fingerprint('ActiveRecord::RecordNotFound', 'Reports::TasksController#index'),
          count: 5,
          first_seen_at: 2.days.ago,
          last_seen_at: 12.hours.ago
        )

        issue3 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/reports/base_controller.rb:214',
          controller_action: 'Reports::ShiftsController#index',
          fingerprint: old_style_fingerprint('ActiveRecord::RecordNotFound', 'Reports::ShiftsController#index'),
          count: 3,
          first_seen_at: 1.day.ago,
          last_seen_at: 6.hours.ago
        )

        # Run the recomputer
        stats = described_class.new(dry_run: false).call

        # Should have merged 2 issues into 1
        expect(stats[:merged]).to eq(2)

        # Only 1 issue should remain
        remaining_issues = Issue.where(project: project, exception_class: 'ActiveRecord::RecordNotFound')
        expect(remaining_issues.count).to eq(1)

        # The remaining issue should have combined counts
        merged_issue = remaining_issues.first
        expect(merged_issue.count).to eq(18) # 10 + 5 + 3

        # Should have earliest first_seen_at and latest last_seen_at
        expect(merged_issue.first_seen_at).to be_within(1.second).of(3.days.ago)
        expect(merged_issue.last_seen_at).to be_within(1.second).of(6.hours.ago)
      end

      it 'moves events from merged issues to the target issue' do
        issue1 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show',
          fingerprint: old_style_fingerprint('ActiveRecord::RecordNotFound', 'UsersController#show'),
          count: 2
        )
        event1 = create(:event, project: project, issue: issue1)
        event2 = create(:event, project: project, issue: issue1)

        issue2 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'ProjectsController#show',
          fingerprint: old_style_fingerprint('ActiveRecord::RecordNotFound', 'ProjectsController#show'),
          count: 1
        )
        event3 = create(:event, project: project, issue: issue2)

        described_class.new(dry_run: false).call

        # All events should now belong to the surviving issue
        remaining_issue = Issue.where(project: project, exception_class: 'ActiveRecord::RecordNotFound').first
        expect(remaining_issue.events.count).to eq(3)
        expect(Event.where(id: [event1.id, event2.id, event3.id]).pluck(:issue_id).uniq).to eq([remaining_issue.id])
      end
    end

    context 'when issues already have correct fingerprints' do
      it 'does not change issues that already have correct fingerprints' do
        # Create issue with NEW-style fingerprint (already correct)
        new_fingerprint = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/users_controller.rb:30',
          'UsersController#show'
        )

        issue = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/users_controller.rb:30',
          controller_action: 'UsersController#show',
          fingerprint: new_fingerprint,
          count: 5
        )

        stats = described_class.new(dry_run: false).call

        expect(stats[:unchanged]).to eq(1)
        expect(stats[:merged]).to eq(0)
        expect(stats[:updated]).to eq(0)

        issue.reload
        expect(issue.fingerprint).to eq(new_fingerprint)
        expect(issue.count).to eq(5)
      end
    end

    context 'when issues need fingerprint update but no merge' do
      it 'updates fingerprint without merging when no duplicate exists' do
        # Issue with old fingerprint but no other issue to merge with
        issue = create(:issue,
          project: project,
          exception_class: 'RuntimeError',
          top_frame: 'app/services/payment.rb:100',
          controller_action: 'PaymentsController#create',
          fingerprint: 'old_fingerprint_that_needs_update',
          count: 3
        )

        expected_fingerprint = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/payment.rb:100',
          'PaymentsController#create'
        )

        stats = described_class.new(dry_run: false).call

        expect(stats[:updated]).to eq(1)
        expect(stats[:merged]).to eq(0)

        issue.reload
        expect(issue.fingerprint).to eq(expected_fingerprint)
      end
    end

    context 'dry run mode' do
      it 'does not make any changes in dry run mode' do
        issue1 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show',
          fingerprint: 'old_fingerprint_1',
          count: 10
        )

        issue2 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'ProjectsController#show',
          fingerprint: 'old_fingerprint_2',
          count: 5
        )

        original_count = Issue.count
        original_fingerprint1 = issue1.fingerprint
        original_fingerprint2 = issue2.fingerprint

        stats = described_class.new(dry_run: true).call

        # Stats should show what would happen
        expect(stats[:merged]).to eq(1)

        # But no actual changes
        expect(Issue.count).to eq(original_count)
        expect(issue1.reload.fingerprint).to eq(original_fingerprint1)
        expect(issue2.reload.fingerprint).to eq(original_fingerprint2)
      end
    end

    context 'cross-project isolation' do
      it 'does not merge issues across different projects' do
        other_project = create(:project, account: account)

        # Same exception, same origin, but different projects
        issue1 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show',
          fingerprint: 'old_fingerprint_project1',
          count: 10
        )

        issue2 = create(:issue,
          project: other_project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show',
          fingerprint: 'old_fingerprint_project2',
          count: 5
        )

        stats = described_class.new(dry_run: false).call

        # Both issues should be updated (new fingerprints) but NOT merged
        expect(stats[:updated]).to eq(2)
        expect(stats[:merged]).to eq(0)

        # Both issues should still exist
        expect(Issue.exists?(issue1.id)).to be true
        expect(Issue.exists?(issue2.id)).to be true
      end
    end

    context 'different exception types' do
      it 'does not merge different exception types from same origin' do
        issue1 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show',
          fingerprint: 'old_fingerprint_1',
          count: 10
        )

        issue2 = create(:issue,
          project: project,
          exception_class: 'ActiveRecord::RecordInvalid',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show',
          fingerprint: 'old_fingerprint_2',
          count: 5
        )

        stats = described_class.new(dry_run: false).call

        # Both should be updated but NOT merged (different exception types)
        expect(stats[:updated]).to eq(2)
        expect(stats[:merged]).to eq(0)

        expect(Issue.exists?(issue1.id)).to be true
        expect(Issue.exists?(issue2.id)).to be true
      end
    end

    context 'real-world Rescuehub scenario' do
      it 'merges the 3 Reports controller errors into 1 issue' do
        # Exact scenario: 3 RecordNotFound errors from different Reports controllers
        # all originating from authenticate_with_bearer_token in base_controller.rb:214

        issues_data = [
          { controller: 'Reports::HoursController#index', count: 2 },
          { controller: 'Reports::TasksController#index', count: 1 },
          { controller: 'Reports::ShiftsController#index', count: 1 }
        ]

        issues = issues_data.map do |data|
          create(:issue,
            project: project,
            exception_class: 'ActiveRecord::RecordNotFound',
            top_frame: '/var/app/current/app/controllers/reports/base_controller.rb:214',
            controller_action: data[:controller],
            fingerprint: Digest::SHA256.hexdigest("ActiveRecord::RecordNotFound|#{data[:controller]}"),
            count: data[:count],
            sample_message: "Couldn't find Organization with 'id'=10"
          )
        end

        # Create some events for each issue
        issues.each do |issue|
          create(:event, project: project, issue: issue)
        end

        stats = described_class.new(dry_run: false).call

        # Should merge 2 issues
        expect(stats[:merged]).to eq(2)

        # Only 1 issue should remain
        remaining = Issue.where(project: project, exception_class: 'ActiveRecord::RecordNotFound')
        expect(remaining.count).to eq(1)

        # Combined count should be 4 (2 + 1 + 1)
        expect(remaining.first.count).to eq(4)

        # All 3 events should be on the surviving issue
        expect(remaining.first.events.count).to eq(3)
      end
    end

    context 'error handling' do
      it 'continues processing after an error and tracks error count' do
        # Create a valid issue
        valid_issue = create(:issue,
          project: project,
          exception_class: 'RuntimeError',
          top_frame: 'app/services/test.rb:1',
          controller_action: 'TestController#action',
          fingerprint: 'valid_fingerprint',
          count: 1
        )

        # Stub to cause an error on specific issue
        allow(Issue).to receive(:send).and_call_original
        allow(Issue).to receive(:send).with(:generate_fingerprint, 'RuntimeError', 'app/services/test.rb:1', 'TestController#action').and_raise(StandardError, 'Test error')

        stats = described_class.new(dry_run: false).call

        expect(stats[:errors]).to eq(1)
        expect(stats[:processed]).to eq(1)
      end
    end
  end
end
