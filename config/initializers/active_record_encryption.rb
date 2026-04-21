primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

if Rails.env.production?
  missing = {
    "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => primary_key,
    "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => deterministic_key,
    "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => key_derivation_salt
  }.select { |_, v| v.blank? }.keys

  if missing.any?
    raise "Missing Active Record encryption ENV vars: #{missing.join(', ')}. " \
          "Generate with `bin/rails db:encryption:init` and set before boot."
  end
else
  primary_key ||= "development_primary_key_not_for_production_use_32"
  deterministic_key ||= "development_deterministic_key_not_for_prod"
  key_derivation_salt ||= "development_key_derivation_salt_not_for_prod"
end

Rails.application.config.active_record.encryption.primary_key = primary_key
Rails.application.config.active_record.encryption.deterministic_key = deterministic_key
Rails.application.config.active_record.encryption.key_derivation_salt = key_derivation_salt
