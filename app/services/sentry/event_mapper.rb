# Maps a normalized Sentry issue payload (see Sentry::Client) to an Issue row.
#
# Caller is responsible for being inside an ActsAsTenant block scoped to
# project.account before calling.
module Sentry
  class EventMapper
    UNKNOWN_PLACEHOLDER = "(sentry-unknown)"

    # Upserts an Issue keyed by fingerprint "sentry:<sentry_issue_id>" within
    # the given project. Returns the persisted Issue.
    def self.upsert!(project, payload)
      fingerprint = "sentry:#{payload[:sentry_issue_id]}"
      issue = project.issues.find_or_initialize_by(fingerprint: fingerprint)

      now = Time.current
      last_seen = parse_time(payload[:last_seen]) || now
      culprit = payload[:culprit].presence || UNKNOWN_PLACEHOLDER

      attrs = {
        exception_class: payload[:exception_class].presence || "UnknownError",
        sample_message: payload[:title],
        source: "sentry",
        last_seen_at: last_seen,
        # Required NOT NULL columns — fall back to the Sentry culprit so the
        # row can satisfy presence validations even though Sentry doesn't give
        # us a real stack frame here.
        top_frame: culprit,
        controller_action: culprit
      }

      # `count` is the running event count on the Issue; trust Sentry's number
      # when present so subsequent upserts reflect updated frequency.
      if payload[:event_count]
        attrs[:count] = payload[:event_count].to_i
      end

      # On first insert we must set first_seen_at (NOT NULL).
      if issue.new_record?
        attrs[:first_seen_at] = last_seen
      end

      issue.assign_attributes(attrs.compact)
      issue.save!
      issue
    end

    def self.parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :parse_time
  end
end
