# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'issues rake tasks', type: :task do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }

  before(:all) do
    Rails.application.load_tasks
  end

  before do
    ActsAsTenant.current_tenant = account
    # Reset task so it can be invoked multiple times in tests
    Rake::Task['issues:recompute_fingerprints'].reenable
    Rake::Task['issues:preview_fingerprint_changes'].reenable
  end

  describe 'issues:recompute_fingerprints' do
    it 'runs in dry_run mode by default when passed true' do
      issue = create(:issue,
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/base.rb:50',
        controller_action: 'UsersController#show',
        fingerprint: 'old_fingerprint',
        count: 5
      )

      original_fingerprint = issue.fingerprint

      expect {
        Rake::Task['issues:recompute_fingerprints'].invoke('true')
      }.to output(/DRY RUN/).to_stdout

      # Fingerprint should NOT change in dry run
      expect(issue.reload.fingerprint).to eq(original_fingerprint)
    end

    it 'applies changes when dry_run is false' do
      issue = create(:issue,
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/base.rb:50',
        controller_action: 'UsersController#show',
        fingerprint: 'old_fingerprint',
        count: 5
      )

      Rake::Task['issues:recompute_fingerprints'].reenable

      expect {
        Rake::Task['issues:recompute_fingerprints'].invoke('false')
      }.to output(/Updating fingerprint/).to_stdout

      expected_fingerprint = Issue.send(:generate_fingerprint,
        'ActiveRecord::RecordNotFound',
        'app/controllers/base.rb:50',
        'UsersController#show'
      )

      expect(issue.reload.fingerprint).to eq(expected_fingerprint)
    end

    it 'outputs summary statistics' do
      create(:issue,
        project: project,
        exception_class: 'RuntimeError',
        top_frame: 'app/test.rb:1',
        controller_action: 'TestController#action',
        fingerprint: 'needs_update'
      )

      output = capture_stdout do
        Rake::Task['issues:recompute_fingerprints'].invoke('true')
      end

      expect(output).to include('Issue Fingerprint Recomputation')
      expect(output).to include('Issues processed:')
      expect(output).to include('Issues merged:')
      expect(output).to include('Issues updated:')
      expect(output).to include('Summary')
    end

    it 'respects DRY_RUN environment variable' do
      issue = create(:issue,
        project: project,
        exception_class: 'RuntimeError',
        top_frame: 'app/test.rb:1',
        controller_action: 'TestController#action',
        fingerprint: 'old_fp'
      )

      original_fp = issue.fingerprint

      ClimateControl.modify(DRY_RUN: 'true') do
        Rake::Task['issues:recompute_fingerprints'].reenable
        capture_stdout { Rake::Task['issues:recompute_fingerprints'].invoke }
      end

      expect(issue.reload.fingerprint).to eq(original_fp)
    end
  end

  describe 'issues:preview_fingerprint_changes' do
    it 'is an alias for dry run mode' do
      issue = create(:issue,
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/base.rb:50',
        controller_action: 'UsersController#show',
        fingerprint: 'old_fingerprint'
      )

      original_fingerprint = issue.fingerprint

      expect {
        Rake::Task['issues:preview_fingerprint_changes'].invoke
      }.to output(/DRY RUN/).to_stdout

      expect(issue.reload.fingerprint).to eq(original_fingerprint)
    end
  end

  # Helper to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
