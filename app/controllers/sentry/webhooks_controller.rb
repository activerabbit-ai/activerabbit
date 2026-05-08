module Sentry
  class WebhooksController < ActionController::API
    def receive
      project = ActsAsTenant.without_tenant { Project.find_by(id: params[:project_id]) }
      return head :not_found unless project

      raw = request.raw_post
      secret = project.settings.to_h["sentry_webhook_secret"]
      sig    = request.headers["Sentry-Hook-Signature"].to_s
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, raw)
      return head :unauthorized if sig.empty? || !ActiveSupport::SecurityUtils.secure_compare(expected, sig)

      payload = JSON.parse(raw) rescue {}
      Sentry::IngestEventJob.perform_later(project.id, payload)
      head :ok
    end
  end
end
