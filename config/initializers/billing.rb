Rails.application.configure do
  config.x.trial_days = (ENV["TRIAL_DAYS"] || 14).to_i
end
