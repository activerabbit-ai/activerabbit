begin
  require "bullet"
  Rails.application.configure do
    config.after_initialize do
      if defined?(Bullet) && Bullet.respond_to?(:enable=)
        Bullet.enable = true
        Bullet.alert = true
        Bullet.bullet_logger = true
        Bullet.console = true
        Bullet.rails_logger = true
        Bullet.add_footer = true
      end
    end
  end
rescue LoadError, StandardError
  # Bullet not available or incompatible; skip configuration
end
