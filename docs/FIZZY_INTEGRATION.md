# Fizzy Integration

ActiveRabbit can sync errors to [Fizzy](https://github.com/basecamp/fizzy) boards, creating cards for each issue so your team can track and triage errors directly in Fizzy.

## Configuration

### Via Project Settings UI

1. Navigate to your project's Settings page
2. Find the "Fizzy Integration" card
3. Enter your Fizzy Endpoint URL (e.g., `https://fizzy.app/account/boards/abc123`)
   - You can include `/cards` at the end or omit it - both formats work
   - Example: `https://fizzy.app/123456/boards/abc123` or `https://fizzy.app/123456/boards/abc123/cards`
4. Enter your Fizzy API Key
5. Click "Save Fizzy Settings"

### Via Environment Variables

For production deployments, configure Fizzy via environment variables:

```bash
# Global settings (apply to all projects)
FIZZY_ENDPOINT_URL=https://fizzy.app/account/boards/abc123
FIZZY_API_KEY=your_api_key_here

# Project-specific settings (override global)
FIZZY_ENDPOINT_URL_MY_PROJECT=https://fizzy.app/account/boards/xyz789
FIZZY_API_KEY_MY_PROJECT=project_specific_key
```

Project-specific variables use the project slug in uppercase (e.g., `my-project` becomes `MY_PROJECT`).

## Features

### Auto-Sync New Errors

When enabled, ActiveRabbit automatically creates Fizzy cards when new errors occur. Toggle this in project settings under "Auto-sync new errors".

### Manual Sync

Click "Sync All Open Issues" to manually sync all open issues to Fizzy. This is useful for:
- Initial sync after configuring the integration
- Syncing issues that occurred before enabling auto-sync
- Re-syncing after cleaning up issues

Manual sync works independently of the auto-sync toggle.

### Duplicate Prevention

The sync process checks for existing cards with matching titles before creating new ones. This prevents duplicates when:
- Re-running manual sync
- Cards have been moved between columns in Fizzy
- Multiple sync attempts occur

### Test Connection

Use "Test Connection" to verify your Fizzy configuration is correct. This creates a test card in your Fizzy board.

## Card Format

Each synced error creates a Fizzy card with:

- **Title**: `{ExceptionClass} in {Controller#Action}`
- **Description**: Error details including:
  - Error message
  - Request path and method
  - Environment
  - Occurrence count
  - First seen timestamp
  - Stack trace (first 10 lines)
  - Context data (if available)

## API Endpoints Used

ActiveRabbit uses the following Fizzy API endpoints:

- `POST /:account/boards/:board_id/cards` - Create new cards
- `GET /:account/cards` - Fetch existing cards (for duplicate checking)

## Troubleshooting

### Cards Not Syncing

1. Check that both Endpoint URL and API Key are configured
2. Verify the API key has permission to create cards
3. Check Rails logs for detailed error messages

### Duplicate Cards

If duplicates are being created:
1. Ensure the endpoint URL includes the correct board ID
2. Check that the Fizzy API is returning all cards (not paginated)
3. Verify card titles match exactly (case-sensitive)

### Connection Errors

Common issues:
- **Timeout**: Fizzy server may be slow or unreachable
- **401 Unauthorized**: Check API key is correct
- **404 Not Found**: Verify endpoint URL and board ID
- **422 Validation Error**: Check card payload format

## Background Jobs

Fizzy sync runs in Sidekiq background jobs:
- `FizzyBatchSyncJob` - Syncs all open issues for a project

Ensure Sidekiq is running to process sync jobs.
