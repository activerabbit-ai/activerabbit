class Rack::Attack
  # Configure Cache
  # If you don't want to use Rails.cache (Rack::Attack's default), then
  # configure it here.
  #
  # Note: The store is only used for throttling (not blacklisting and
  # whitelisting). It must implement .read, .write and .delete methods.
  # Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Allow all local traffic
  safelist('allow-localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1'
  end

  # Allow an IP address to make 5 requests every 5 seconds
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Throttle login attempts by IP address
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email address
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      # Normalize the email, using the same logic as your authentication process, to
      # protect against rate limit bypasses. Return the normalized email if present, nil otherwise.
      req.params['user']['email'].to_s.downcase.gsub(/\s+/, "") if req.params['user']
    end
  end

  # Throttle password reset attempts by IP address
  throttle('password_resets/ip', limit: 5, period: 60.seconds) do |req|
    if req.path == '/users/password' && req.post?
      req.ip
    end
  end

  # Throttle sign up attempts by IP address
  throttle('registrations/ip', limit: 5, period: 60.seconds) do |req|
    if req.path == '/users' && req.post?
      req.ip
    end
  end

  # Block suspicious requests
  blocklist('fail2ban pentesters') do |req|
    # `filter` returns truthy value if request fails, or if it's from a previously banned IP
    # so the request is blocked
    Rack::Attack::Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 3, findtime: 10.minutes, bantime: 5.minutes) do
      # The count for the IP is incremented if the return value is truthy
      CGI.unescape(req.query_string) =~ %r{/etc/passwd} ||
      req.path.include?('/etc/passwd') ||
      req.path.include?('wp-admin') ||
      req.path.include?('wp-login') ||
      req.path.include?('.php') ||
      req.path.include?('phpmyadmin')
    end
  end

  # Block requests from bad user agents
  blocklist('bad user agents') do |req|
    req.user_agent =~ /BadBot|ScanBot|sqlmap|nmap|nikto|dirbuster|masscan|zmap/i
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |env|
    retry_after = (env['rack.attack.match_data'] || {})[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{error: "Rate limit exceeded. Try again in #{retry_after} seconds."}.to_json]
    ]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |env|
    [
      403,
      {'Content-Type' => 'application/json'},
      [{error: "Forbidden"}.to_json]
    ]
  end
end

# Enable rack-attack
Rails.application.config.middleware.use Rack::Attack
