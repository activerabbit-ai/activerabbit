module BillingGuard
  extend ActiveSupport::Concern

  # Soft gating only: show banner via shared partial; no redirects here.
  # Keep this module as a no-op to avoid require/load errors if included.
end
