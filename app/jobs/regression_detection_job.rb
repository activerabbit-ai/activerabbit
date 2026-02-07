class RegressionDetectionJob
  include Sidekiq::Job

  sidekiq_options queue: :analysis, retry: 2

  def perform(release_id, account_id = nil)
    # Set tenant for ActsAsTenant scoping
    if account_id
      account = Account.find(account_id)
      ActsAsTenant.with_tenant(account) do
        process_release(release_id)
      end
    else
      # Fallback: find release without tenant (for backwards compatibility)
      release = Release.unscoped.find(release_id)
      ActsAsTenant.with_tenant(release.account) do
        process_release(release_id)
      end
    end
  end

  private

  def process_release(release_id)
    release = Release.find(release_id)

    Rails.logger.info "Starting regression detection for release #{release.version}"

    # Wait a bit for data to be available after deployment
    sleep(30) if Rails.env.production?

    # Detect performance regressions
    regressions = release.detect_performance_regression!

    if regressions.any?
      Rails.logger.warn "Detected #{regressions.size} performance regressions for release #{release.version}"

      # Log each regression
      regressions.each do |regression|
        Rails.logger.warn "Regression in #{regression[:controller_action]}: " \
                         "#{regression[:before_p95]}ms -> #{regression[:after_p95]}ms " \
                         "(+#{regression[:regression_pct]}%)"
      end
    else
      Rails.logger.info "No performance regressions detected for release #{release.version}"
    end

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Release not found for regression detection: #{release_id}"
    raise e
  rescue => e
    Rails.logger.error "Error in regression detection: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end
