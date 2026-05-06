# frozen_string_literal: true

namespace :sre_inbox do
  desc "Analyze the N most recent un-analyzed issues per project (default 20). " \
       "Use this on/after deploy so the inbox isn't empty without burning Claude " \
       "calls on the entire backlog. Usage: bin/rails sre_inbox:backfill[20]"
  task :backfill, [:per_project] => :environment do |_t, args|
    per_project = (args[:per_project].presence || ENV["PER_PROJECT"] || 20).to_i
    queued = 0
    skipped = 0

    ActsAsTenant.without_tenant do
      Project.find_each do |project|
        ActsAsTenant.with_tenant(project.account) do
          batch = Issue.where(project_id: project.id, sre_analyzed_at: nil)
                       .order(last_seen_at: :desc)
                       .limit(per_project)

          batch.each do |issue|
            if Rails.env.development? && ENV["INLINE"].present?
              SreInbox::Analyzer.new(issue).call
            else
              AnalyzeIssueJob.perform_async(issue.id)
            end
            queued += 1
          end

          skipped += [Issue.where(project_id: project.id).count - per_project, 0].max
        end
      end
    end

    inline = (Rails.env.development? && ENV["INLINE"].present?)
    puts "[sre_inbox:backfill] #{inline ? 'analyzed inline' : 'queued'}: #{queued} issues " \
         "(per_project=#{per_project}); skipped ~#{skipped} older issues account-wide."
  end

  desc "Analyze a single issue by id (for debugging). Usage: bin/rails sre_inbox:analyze[123]"
  task :analyze, [:issue_id] => :environment do |_t, args|
    abort "issue_id required" if args[:issue_id].blank?
    ActsAsTenant.without_tenant do
      issue = Issue.find(args[:issue_id])
      result = SreInbox::Analyzer.new(issue).call
      puts result.inspect
    end
  end
end
