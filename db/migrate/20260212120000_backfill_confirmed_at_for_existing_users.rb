# Backfill confirmed_at for all existing users who were created BEFORE
# the email confirmation feature was added (migration 20260205094128).
#
# These users were already active and trusted — they should be grandfathered in
# as confirmed. Without this, all email notifications are silently skipped
# because every mailer/job checks `email_confirmed?` which requires
# `confirmed_at` to be present (or an OAuth `provider`).
class BackfillConfirmedAtForExistingUsers < ActiveRecord::Migration[8.0]
  def up
    # Set confirmed_at for all users who don't have it yet.
    # Use the user's created_at timestamp so it reflects when they originally joined.
    execute <<~SQL
      UPDATE users
      SET confirmed_at = created_at
      WHERE confirmed_at IS NULL
    SQL
  end

  def down
    # No-op: we cannot distinguish backfilled users from genuinely confirmed ones
  end
end
