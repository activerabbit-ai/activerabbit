require "net/http"
require "uri"
require "json"
require "cgi"

class FizzySyncService
  def initialize(project)
    @project = project
    @endpoint_url = normalize_endpoint_url(project.fizzy_endpoint_url)
    @api_key = project.fizzy_api_key
  end

  def configured?
    @endpoint_url.present? && @api_key.present?
  end

  private

  # Ensure the endpoint URL ends with /cards
  def normalize_endpoint_url(url)
    return nil if url.blank?

    url = url.strip.chomp("/") # Remove trailing slash
    url = "#{url}/cards" unless url.end_with?("/cards")
    url
  end

  public

  def sync_error(event)
    result = sync_error_with_response(event)
    result[:success] == true
  end

  def sync_error_with_response(event, force: false)
    unless configured?
      Rails.logger.debug "Fizzy sync skipped: not configured (endpoint: #{@endpoint_url.present? ? 'set' : 'missing'}, api_key: #{@api_key.present? ? 'set' : 'missing'})"
      return { success: false }
    end

    unless force || @project.fizzy_sync_enabled?
      Rails.logger.debug "Fizzy sync skipped: auto-sync disabled for project #{@project.id}"
      return { success: false }
    end

    Rails.logger.info "Syncing error event #{event.id} to Fizzy"
    payload = build_error_payload(event)
    result = send_to_fizzy(payload)

    if result[:success]
      Rails.logger.info "Successfully synced error event #{event.id} to Fizzy"
    else
      Rails.logger.error "Failed to sync error event #{event.id} to Fizzy: #{result[:error]}"
    end

    result
  rescue StandardError => e
    Rails.logger.error "Failed to sync error #{event.id} to Fizzy: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Don't raise - we don't want to break error ingestion
    { success: false, error: e.message }
  end

  def sync_issue(issue, force: false, existing_cards: nil)
    return false unless configured?
    return false unless force || @project.fizzy_sync_enabled?

    expected_title = "#{issue.exception_class} in #{issue.controller_action || 'Unknown'}"

    # Check if card already exists in Fizzy
    if force && existing_cards
      # For forced sync, check actual Fizzy cards to avoid duplicates
      matching_card = existing_cards.find { |c| c["title"] == expected_title }
      if matching_card
        Rails.logger.debug "Issue #{issue.id} already has Fizzy card '#{expected_title}', skipping"
        # Update local mapping with the found card
        update_card_mapping(issue, matching_card["number"])
        return true
      end
    else
      # For auto-sync, use local mapping
      card_mapping = @project.settings["fizzy_card_mapping"] || {}
      if card_mapping[issue.fingerprint].present?
        Rails.logger.debug "Issue #{issue.id} (#{issue.fingerprint}) already has Fizzy card ##{card_mapping[issue.fingerprint]}, skipping"
        return true
      end
    end

    # Sync the most recent event for this issue
    event = issue.events.order(occurred_at: :desc).first
    return false unless event

    result_hash = sync_error_with_response(event, force: force)
    result = result_hash[:success]

    # If sync was successful, store the card number
    if result && event.issue.present?
      card_number = result_hash[:card_number] || find_card_number_for_issue(issue)
      update_card_mapping(issue, card_number) if card_number
    end

    result
  rescue StandardError => e
    Rails.logger.error "Failed to sync issue #{issue.id} to Fizzy: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    false
  end

  def update_card_mapping(issue, card_number)
    return unless card_number

    card_mapping = @project.settings["fizzy_card_mapping"] || {}
    card_mapping[issue.fingerprint] = card_number.to_i
    @project.settings = @project.settings.merge("fizzy_card_mapping" => card_mapping)
    @project.save
    Rails.logger.info "Stored Fizzy card ##{card_number} for issue #{issue.id} (#{issue.fingerprint})"
  end

  # Fetch all existing cards from Fizzy for the configured board
  # Uses account-level endpoint with board filtering
  def fetch_existing_cards
    uri = URI.parse(@endpoint_url)
    # Extract account slug and board_id from path like: /338000007/boards/BOARD_ID/cards
    path_parts = uri.path.split("/").reject(&:blank?)
    account_slug = path_parts[0]
    board_id = path_parts[2] if path_parts[1] == "boards"

    return [] unless account_slug

    # Use account-level cards endpoint with board_id filter if supported
    # Try to get more cards by adding per_page parameter
    cards_path = "/#{account_slug}/cards"
    query_params = []
    query_params << "board_id=#{board_id}" if board_id
    query_params << "per_page=500"  # Request more cards to avoid pagination
    cards_path += "?#{query_params.join('&')}" if query_params.any?

    cards_endpoint = "#{uri.scheme}://#{uri.host}:#{uri.port}#{cards_path}"
    cards_uri = URI.parse(cards_endpoint)

    http = Net::HTTP.new(cards_uri.host, cards_uri.port)
    http.use_ssl = (cards_uri.scheme == "https")
    http.read_timeout = 10

    request_path = cards_uri.path
    request_path += "?#{cards_uri.query}" if cards_uri.query.present?

    Rails.logger.info "Fetching existing cards from: #{cards_endpoint}"
    request = Net::HTTP::Get.new(request_path)
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{@api_key}"

    response = http.request(request)

    # Log pagination Link header if present (for debugging)
    link_header = response["Link"]
    Rails.logger.debug "Pagination Link header: #{link_header}" if link_header

    if response.code.to_i == 200
      cards = JSON.parse(response.body) rescue []
      Rails.logger.info "Fetched #{cards.size} existing cards from Fizzy for duplicate check"

      # Filter to only cards on our board (in case API doesn't support board_id filter)
      if board_id
        board_id_str = board_id.to_s
        before_count = cards.size
        cards = cards.select do |c|
          card_board_id = (c["board_id"] || c.dig("board", "id")).to_s
          card_board_id == board_id_str
        end
        Rails.logger.info "Filtered to #{cards.size} cards for board #{board_id}" if before_count != cards.size
      end

      Rails.logger.debug "Existing card titles: #{cards.map { |c| c['title'] }.inspect}"
      cards
    else
      Rails.logger.warn "Could not fetch existing cards from Fizzy: #{response.code} - #{response.body&.truncate(200)}"
      []
    end
  rescue StandardError => e
    Rails.logger.warn "Error fetching existing cards from Fizzy: #{e.message}"
    Rails.logger.warn e.backtrace.first(5).join("\n")
    []
  end

  def find_card_number_for_issue(issue)
    # Fetch existing cards and find matching one
    cards = fetch_existing_cards
    expected_title = "#{issue.exception_class} in #{issue.controller_action || 'Unknown'}"

    matching_card = cards.find { |c| c["title"] == expected_title }
    matching_card ? matching_card["number"] : nil
  rescue StandardError => e
    Rails.logger.warn "Could not find card number for issue #{issue.id}: #{e.message}"
    nil
  end

  def sync_batch(issues, force: false)
    return { synced: 0, failed: 0, total: 0, error: "Fizzy not configured" } unless configured?
    return { synced: 0, failed: 0, total: 0, error: "Fizzy sync disabled" } unless force || @project.fizzy_sync_enabled?

    synced_count = 0
    failed_count = 0
    skipped_count = 0
    total_count = issues.count

    # For forced sync, fetch existing cards from Fizzy to check for duplicates
    existing_cards = force ? fetch_existing_cards : nil
    Rails.logger.info "Fizzy batch sync: #{total_count} issues to process#{force ? ' (forced)' : ''}"

    issues.find_each do |issue|
      if sync_issue(issue, force: force, existing_cards: existing_cards)
        synced_count += 1
        Rails.logger.debug "Successfully synced issue #{issue.id} to Fizzy"
      else
        failed_count += 1
        Rails.logger.warn "Failed to sync issue #{issue.id} to Fizzy"
      end
    end

    result = {
      synced: synced_count,
      failed: failed_count,
      total: synced_count + failed_count
    }

    Rails.logger.info "Fizzy batch sync completed: #{synced_count} synced, #{failed_count} failed out of #{total_count} total"
    result
  rescue StandardError => e
    Rails.logger.error "Failed to batch sync to Fizzy: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { synced: 0, failed: 0, total: 0, error: e.message }
  end

  def test_connection
    return { success: false, error: "Fizzy not configured" } unless configured?

    # Create a test card payload according to Fizzy API format
    test_payload = {
      card: {
        title: "Test sync from ActiveRabbit",
        description: "<p>This is a test card created by ActiveRabbit to verify the integration is working correctly.</p><p><strong>Project:</strong> #{CGI.escapeHTML(@project.name)}</p><p><strong>Timestamp:</strong> #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}</p>"
      }
    }

    response = send_to_fizzy(test_payload)
    if response[:success]
      { success: true, message: "Successfully connected to Fizzy and created test card" }
    else
      { success: false, error: response[:error] || "Unknown error" }
    end
  rescue StandardError => e
    Rails.logger.error "Fizzy test connection failed: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def build_error_payload(event)
    # Format as a Fizzy card according to API docs
    # https://github.com/basecamp/fizzy/blob/main/docs/API.md
    title = "#{event.exception_class} in #{event.controller_action || 'Unknown'}"

    # Build description with error details
    description_parts = []
    description_parts << "<p><strong>Error:</strong> #{CGI.escapeHTML(event.message)}</p>"

    if event.request_path.present?
      description_parts << "<p><strong>Path:</strong> #{CGI.escapeHTML(event.request_method || 'GET')} #{CGI.escapeHTML(event.request_path)}</p>"
    end

    description_parts << "<p><strong>Environment:</strong> #{CGI.escapeHTML(event.environment || 'production')}</p>"

    if event.occurred_at.present?
      description_parts << "<p><strong>Occurred At:</strong> #{event.occurred_at.strftime('%Y-%m-%d %H:%M:%S UTC')}</p>"
    end

    if event.issue.present?
      description_parts << "<p><strong>Occurrences:</strong> #{event.issue.count}</p>"
      description_parts << "<p><strong>First Seen:</strong> #{event.issue.first_seen_at&.strftime('%Y-%m-%d %H:%M:%S UTC')}</p>"
    end

    # Add backtrace if available
    if event.formatted_backtrace.present? && event.formatted_backtrace.any?
      description_parts << "<p><strong>Stack Trace:</strong></p>"
      description_parts << "<pre>#{CGI.escapeHTML(event.formatted_backtrace.first(10).join("\n"))}</pre>"
    end

    # Add context if available
    if event.context.present? && event.context.any?
      description_parts << "<p><strong>Context:</strong></p>"
      description_parts << "<pre>#{CGI.escapeHTML(JSON.pretty_generate(event.context))}</pre>"
    end

    description = description_parts.join("\n")

    card_data = {
      title: title,
      description: description
    }

    # Add column_id if configured
    column_id = @project.settings["fizzy_column_id"]
    card_data[:column_id] = column_id if column_id.present?

    # Add tag_ids if configured
    tag_ids = @project.settings["fizzy_tag_ids"]
    if tag_ids.present?
      tag_ids_array = tag_ids.is_a?(Array) ? tag_ids : tag_ids.split(",").map(&:strip)
      card_data[:tag_ids] = tag_ids_array if tag_ids_array.any?
    end

    {
      card: card_data
    }
  end

  def send_to_fizzy(payload)
    begin
      uri = URI.parse(@endpoint_url)
    rescue URI::InvalidURIError => e
      error_msg = "Invalid Fizzy endpoint URL: #{@endpoint_url} - #{e.message}"
      Rails.logger.error error_msg
      return { success: false, error: error_msg }
    end

    # Set default port if not specified
    port = uri.port || (uri.scheme == "https" ? 443 : 80)

    http = Net::HTTP.new(uri.host, port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = 10
    http.open_timeout = 5

    # Include query string if present
    path = uri.path
    path += "?#{uri.query}" if uri.query.present?

    request = Net::HTTP::Post.new(path)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{@api_key}"
    request.body = payload.to_json

    Rails.logger.info "Fizzy sync: POST #{@endpoint_url}"
    Rails.logger.debug "Fizzy sync payload: #{payload.to_json}"

    response = http.request(request)

    Rails.logger.debug "Fizzy API response: #{response.code} #{response.message}"
    Rails.logger.debug "Fizzy API response body: #{response.body}" if response.body.present?

    status_code = response.code.to_i

    if status_code >= 200 && status_code < 300
      Rails.logger.info "Fizzy sync successful: #{status_code} - Card created"
      location = response["Location"]
      card_number = nil
      if location
        Rails.logger.info "Fizzy card location: #{location}"
        # Extract card number from location URL (strip .json extension if present)
        card_number = location.split("/").last&.sub(/\.json\z/, "")
        Rails.logger.info "Fizzy card number: #{card_number}"
      end
      { success: true, response: response.body, location: location, card_number: card_number }
    else
      # Try to parse error response as JSON
      error_details = ""
      begin
        if response.body.present?
          parsed_error = JSON.parse(response.body)
          if parsed_error.is_a?(Hash)
            error_details = parsed_error.inspect.truncate(200)
            # Extract validation errors if present
            if parsed_error.any? { |k, v| v.is_a?(Array) }
              validation_errors = parsed_error.select { |k, v| v.is_a?(Array) }
              error_details += " Validation errors: #{validation_errors.inspect}".truncate(200)
            end
          end
        end
      rescue JSON::ParserError
        # Not JSON (likely HTML error page), just note the content type
        content_type = response["Content-Type"] || "unknown"
        error_details = "(#{content_type} response)"
      end

      error_msg = "Fizzy API returned #{status_code}: #{error_details}".truncate(300)
      Rails.logger.error error_msg
      Rails.logger.error "Request URL: #{@endpoint_url}"
      Rails.logger.error "Request path: #{path}"
      Rails.logger.error "Request headers: Authorization: Bearer #{@api_key[0..10]}..."
      Rails.logger.error "Request payload: #{payload.to_json}"
      Rails.logger.error "Response headers: #{response.to_hash.inspect}"
      { success: false, error: error_msg, status_code: status_code, response_body: response.body }
    end
  rescue Net::TimeoutError => e
    error_msg = "Timeout connecting to Fizzy: #{e.message}"
    Rails.logger.error error_msg
    { success: false, error: error_msg }
  rescue Errno::ECONNREFUSED => e
    error_msg = "Connection refused to Fizzy endpoint: #{e.message}"
    Rails.logger.error error_msg
    { success: false, error: error_msg }
  rescue StandardError => e
    error_msg = "Error syncing to Fizzy: #{e.message}"
    Rails.logger.error error_msg
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: error_msg }
  end
end
