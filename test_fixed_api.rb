#!/usr/bin/env ruby
# Test the fixed ActiveRabbit API

require 'net/http'
require 'json'
require 'time'

puts "🔧 Testing Fixed ActiveRabbit API"
puts "=" * 50

# Your configuration
API_KEY = "9b3344ba8775e8ab11fd47e04534ae81e938180a23de603e60b5ec4346652f06"
PROJECT_ID = "1"
API_URL = "http://localhost:3000"

# Test the fixed performance endpoint
puts "\n⚡ Testing FIXED performance tracking..."
begin
  uri = URI("#{API_URL}/api/v1/events/performance")
  http = Net::HTTP.new(uri.host, uri.port)

  request = Net::HTTP::Post.new(uri.path)
  request['Content-Type'] = 'application/json'
  request['X-Project-Token'] = API_KEY
  request['X-Project-ID'] = PROJECT_ID

  performance_data = {
    name: "controller.action",
    duration_ms: 150.5,
    metadata: {
      controller: "TestController",
      action: "index",
      method: "GET",
      path: "/test"
    },
    timestamp: Time.now.iso8601(3),
    environment: "development",
    event_type: "performance"
  }

  request.body = JSON.generate(performance_data)

  response = http.request(request)

  puts "Status: #{response.code}"
  puts "Response: #{response.body}"

  if response.code.to_i == 201
    puts "✅ Performance tracking FIXED and working!"
  else
    puts "❌ Still having issues: #{response.code}"
  end
rescue => e
  puts "❌ Performance tracking error: #{e.message}"
end

# Test connection endpoint
puts "\n📡 Testing connection endpoint..."
begin
  uri = URI("#{API_URL}/api/v1/test/connection")
  http = Net::HTTP.new(uri.host, uri.port)

  request = Net::HTTP::Post.new(uri.path)
  request['Content-Type'] = 'application/json'
  request['X-Project-Token'] = API_KEY
  request['X-Project-ID'] = PROJECT_ID
  request.body = JSON.generate({
    gem_version: "0.3.1",
    timestamp: Time.now.iso8601
  })

  response = http.request(request)

  puts "Status: #{response.code}"
  puts "Response: #{response.body}"

  if response.code.to_i == 200
    puts "✅ Connection test successful!"
  else
    puts "❌ Connection test failed: #{response.code}"
  end
rescue => e
  puts "❌ Connection test error: #{e.message}"
end

puts "\n" + "=" * 50
puts "🎉 API fix test completed!"
puts "=" * 50
