# Configure Rack::Attack for security and rate limiting

class Rack::Attack
  # Always allow requests from localhost in development
  safelist('allow-localhost') do |req|
    '127.0.0.1' == req.ip || '::1' == req.ip if Rails.env.development?
  end

  # Allow higher limits for authenticated API requests
  safelist('api-authenticated') do |req|
    req.path.start_with?('/api/') && req.get_header('X-Project-Token').present?
  end

  ### Throttles ###

  # Throttle API requests by IP
  throttle('api/ip', limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?('/api/')
  end

  # Throttle API requests by token (more generous for authenticated requests)
  throttle('api/token', limit: 1000, period: 1.minute) do |req|
    if req.path.start_with?('/api/') && (token = req.get_header('X-Project-Token'))
      # Use token as the key for rate limiting
      Digest::SHA256.hexdigest(token)
    end
  end

  # Throttle login attempts
  throttle('login/email', limit: 10, period: 1.hour) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.params.dig('user', 'email')&.downcase
    end
  end

  # Throttle login attempts by IP
  throttle('login/ip', limit: 20, period: 1.hour) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.ip
    end
  end

  # Throttle registration attempts
  throttle('registration/ip', limit: 5, period: 1.hour) do |req|
    if req.path == '/users' && req.post?
      req.ip
    end
  end

  # General request throttling by IP (very generous)
  throttle('req/ip', limit: 2000, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets')
  end

  ### Blocks ###

  # Block requests with suspicious user agents
  blocklist('bad-user-agents') do |req|
    # Block common attack patterns
    user_agent = req.user_agent.to_s.downcase
    user_agent.include?('sqlmap') ||
    user_agent.include?('nikto') ||
    user_agent.include?('nessus') ||
    user_agent.include?('masscan') ||
    user_agent.include?('nmap') ||
    user_agent.empty?
  end

  # Block requests with suspicious paths
  blocklist('bad-paths') do |req|
    path = req.path.downcase
    # Common attack paths
    path.include?('wp-admin') ||
    path.include?('wp-login') ||
    path.include?('phpmyadmin') ||
    path.include?('admin/config.php') ||
    path.include?('.env') ||
    path.include?('../') ||
    path.include?('..\\')
  end

  # Block requests with suspicious parameters
  blocklist('bad-params') do |req|
    # Check for SQL injection patterns
    req.params.any? do |key, value|
      value.to_s.match?(/union.*select|drop.*table|insert.*into|delete.*from|update.*set/i)
    end
  end

  ### Custom responses ###

  self.throttled_responder = lambda do |env|
    match_data = env['rack.attack.match_data']
    now = match_data[:epoch_time]

    headers = {
      'Content-Type' => 'application/json',
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + match_data[:period]).to_s
    }

    body = {
      error: 'rate_limit_exceeded',
      message: 'Rate limit exceeded. Please slow down.',
      retry_after: match_data[:period]
    }.to_json

    [429, headers, [body]]
  end

  self.blocklisted_responder = lambda do |env|
    [403, { 'Content-Type' => 'application/json' }, [
      {
        error: 'forbidden',
        message: 'Request blocked for security reasons.'
      }.to_json
    ]]
  end

  ### Logging ###

  ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
    request = payload[:request]

    case payload[:match_type]
    when :throttle
      Rails.logger.warn "[Rack::Attack] Throttled #{request.ip} for #{payload[:matched]}: #{request.path}"
    when :blocklist
      Rails.logger.warn "[Rack::Attack] Blocked #{request.ip} for #{payload[:matched]}: #{request.path}"
    end
  end
end

# Enable Rack::Attack in all environments except test
Rails.application.configure do
  config.middleware.use Rack::Attack unless Rails.env.test?
end
