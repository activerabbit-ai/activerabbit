class NPlusOneAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 2

  def perform(project_id, incidents)
    project = Project.find(project_id)

    # Check N+1 alert rules
    AlertRule.check_n_plus_one_rules(project, incidents)

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Project not found for N+1 alert: #{project_id}"
  rescue => e
    Rails.logger.error "Error in N+1 alert job: #{e.message}"
    raise e
  end
end
