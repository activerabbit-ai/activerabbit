module AutoFix
  class DrainQueueJob < ApplicationJob
    queue_as :default

    def perform
      projects = ActsAsTenant.without_tenant { Project.all.to_a }
      projects.each do |project|
        ActsAsTenant.with_tenant(project.account) { drain(project) }
      end
    end

    private

    def drain(project)
      used = project.issues
                    .where.not(auto_fix_status: nil)
                    .where("auto_fix_attempted_at > ?", 7.days.ago)
                    .count
      return if used >= project.auto_pr_weekly_cap.to_i

      slots = project.auto_pr_weekly_cap.to_i - used
      project.issues
             .where(auto_fix_status: "skipped_capped")
             .order(:created_at)
             .limit(slots)
             .each do |issue|
        issue.update_columns(auto_fix_status: nil)
        AutoFixJob.perform_async(issue.id, project.id)
      end
    end
  end
end
