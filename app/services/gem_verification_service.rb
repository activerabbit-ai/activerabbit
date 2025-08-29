# frozen_string_literal: true

class GemVerificationService
  attr_reader :project

  def initialize(project)
    @project = project
  end

  def verify_connection
    # Check if we've received any events from this project recently
    recent_events_check = check_recent_events
    return recent_events_check if recent_events_check[:success]

    # Check if we have any events at all (maybe they tested before)
    historical_events_check = check_historical_events
    return historical_events_check if historical_events_check[:success]

    # No events found
    no_events_response
  rescue => e
    error_response("Connection test failed: #{e.message}")
  end

  private

  def check_recent_events
    recent_events = project.events.where('created_at > ?', verification_window)

    if recent_events.any?
      success_response('Gem is working correctly! Recent events detected.')
    else
      { success: false, reason: :no_recent_events }
    end
  end

  def check_historical_events
    all_events = project.events.limit(1)

    if all_events.any?
      success_response('Gem was previously connected and working!')
    else
      { success: false, reason: :no_events_ever }
    end
  end

  def no_events_response
    error_response(
      'No events received from your application. Please ensure the gem is properly installed and configured.',
      :no_events_detected
    )
  end

  def success_response(message)
    {
      success: true,
      message: message,
      project_id: project.id,
      project_name: project.name,
      events_count: project.events.count,
      last_event_at: project.events.order(:created_at).last&.created_at
    }
  end

  def error_response(message, error_code = :connection_failed)
    {
      success: false,
      error: message,
      error_code: error_code,
      project_id: project.id,
      project_name: project.name,
      suggestions: error_suggestions(error_code)
    }
  end

  def error_suggestions(error_code)
    case error_code
    when :no_events_detected
      [
        'Verify the gem is added to your Gemfile and bundle install was run',
        'Check that your Rails application has been restarted',
        'Ensure your application can reach the ActiveRabbit API',
        'Try triggering a test error: ActiveRabbit::Client.track_exception(StandardError.new("Test"))',
        'Check your Rails logs for any ActiveRabbit-related errors'
      ]
    when :connection_failed
      [
        'Check your internet connection',
        'Verify the API URL is correct in your configuration',
        'Ensure your API token is valid and active'
      ]
    else
      [
        'Check the ActiveRabbit documentation for troubleshooting steps',
        'Contact support if the issue persists'
      ]
    end
  end

  def verification_window
    30.seconds.ago
  end
end
