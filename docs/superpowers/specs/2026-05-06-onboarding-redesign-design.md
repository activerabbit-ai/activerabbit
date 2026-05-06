# Onboarding Redesign — WOW First Impression

**Date:** 2026-05-06
**Status:** Design — pending user review
**Owner:** @shapalov

## Goal

Replace the current 5-page onboarding (`welcome → new_project → install_gem → verify_gem → setup_github`) with a single Turbo-driven wizard that delivers a "WOW first impression" within minutes of signup: imported errors, a connected GitHub repo, and auto-drafted PRs for the highest-confidence fixes.

## Target user journey

```
Sign up (GitHub OAuth, no credit card — already in place)
  ↓
Step 1: "Where do your errors live?"
  ├─ [Featured] Connect Sentry — paste token, instant 7-day backfill
  └─ [Secondary] Install ActiveRabbit SDK — copy gem snippet, deploy later
  ↓
Step 2: One-click GitHub App install (must be done before errors land
        so the auto-PR pipeline has a target)
  ↓
Step 3: Live status feed (Turbo Streams)
  • "Importing… 23 errors found in last 7 days"
  • "Drafting fixes for top 5 high-confidence errors…"
  • PR rows stream in as they're opened on GitHub
  ↓
User clicks the PRs in their inbox. They merge.
```

## Scope decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| Sentry path mode | **A + B-lite**: API token for backfill + Sentry Internal Integration webhook for live sync | Heavy DSN-proxy not needed; user keeps their existing Sentry SDK and we sit alongside as the AI fix layer |
| Auto-PR trigger | **Confidence threshold only** — no fully-automatic shotgun | User just signed up; we don't ship low-confidence guesses unattended into their repo |
| Default cap | **5 auto-PRs per rolling 7-day window**, user-configurable in Settings (5 / 10 / 20) | Prevents PR spam |
| Step order | **GitHub before errors** | Auto-PR job needs a repo target the moment a high-confidence error lands |
| Featured path | **Sentry primary, SDK secondary** | Only Sentry path delivers WOW in <5 min; SDK requires a deploy |
| App-name capture | **On Step 1, single field above both cards**; auto-suggested from Sentry project on token verify if blank | One ask, no extra page |
| Existing onboarding pages | **Removed entirely** | Cleaner UX; multi-page reload kills the WOW feel |

## Architecture

### New components

**Controllers**
- `OnboardingWizardController` — single shell view, Turbo-Frame-driven.
  Actions: `show`, `submit_source`, `verify_sentry_token`, `start_sentry_import`, `complete`.
- `Sentry::WebhooksController` — `POST /webhooks/sentry/:project_id`. Verifies HMAC; enqueues `Sentry::IngestEventJob`.

**Services** (`app/services/sentry/`)
- `Sentry::Client` — wraps `https://sentry.io/api/0/`. Methods: `verify_token`, `list_organizations`, `list_projects(org)`, `list_issues(org, project_slug, days:, limit:)`, `register_internal_integration(org, webhook_url)`.
- `Sentry::ImportService.call(project, days: 7, limit: 100)` — pulls issues, calls `EventMapper`, broadcasts Turbo Stream rows as it goes.
- `Sentry::EventMapper` — converts Sentry issue payload → ActiveRabbit `Issue` + `Event`. Idempotent upsert keyed on `Issue.fingerprint`.

**Jobs**
- `Sentry::ImportProjectJob` — wraps `ImportService` for Sidekiq.
- `Sentry::IngestEventJob` — handles a single webhook payload.
- `AutoFix::OrchestratorJob` — fires on `Issue` after_create. Decides whether to draft a PR based on confidence + cap.
- `AutoFix::DrainQueueJob` — hourly cron; if cap has freed up (an old `AutoPrEvent` aged past 7d), takes the oldest `auto_fix_status = "queued_capped"` issue and drafts.
- `Github::PrCreationJob` — extracted from `errors_controller#create_pr` so it can be enqueued by `OrchestratorJob` without an HTTP request. Wraps existing `Github::PrService`.

**Models / migrations**
- `Project` — new columns:
  - `auto_pr_weekly_cap:integer default:5 not null`
  - `auto_pr_confidence_threshold:integer default:80 not null` — 0–100 scale matching existing `Issue.sre_confidence`. 0 = off (manual-only mode).
- `Project.settings` (existing JSONB) — new keys:
  - `sentry_org_slug`, `sentry_project_slug`, `sentry_auth_token` (see Security note below), `sentry_webhook_secret`, `sentry_internal_integration_id`, `sentry_initial_import_completed_at`
- `Issue` — new column: `auto_fix_status:string` (nullable; values: `pending`, `low_confidence`, `queued_capped`, `awaiting_github`, `awaiting_analysis`, `pr_drafted`, `pr_failed`)
- New `auto_pr_events` table — `(id, project_id, issue_id, opened_at, github_pr_number, github_pr_url, created_at)`. Index `(project_id, opened_at)`. One row per opened auto-PR; used to compute "PRs opened in last 7 days" without a counter.

**Reusing existing analysis pipeline**
- `Issue.sre_confidence` (0–100 integer) is already populated by `SreInbox::Analyzer` — auto-PR uses this instead of re-scoring.
- `Issue.safe_to_auto_merge` (boolean) and `Issue.fix_diff` (text) are also already populated by the analyzer; both feed into `Github::PrCreationJob` which already exists in spirit (extracted from `errors_controller#create_pr`).
- This means `AutoFix::OrchestratorJob` is a *gate* over the existing analyzer→fix pipeline, not a new scorer.

### Removed
- `OnboardingController` actions: `new_project`, `create_project`, `install_gem`, `verify_gem`, `setup_github` (and their views + routes).
- `welcome` becomes a simple redirect to `/onboarding`.

## Data flow

### Sentry path (WOW)

1. User pastes auth token → `Sentry::Client.verify_token`.
2. Client lists orgs/projects → wizard shows project picker if >1, auto-fills app name.
3. Submit → `Project.create!` with `sentry_*` settings, generates random hex `sentry_webhook_secret`, enqueues `Sentry::ImportProjectJob`.
4. Wizard advances to Step 2 (GitHub). External GitHub flow → existing `/github/app/callback` saves `installation_id` → callback redirects to `/onboarding` (changed from current `project_settings_path`).
5. Step 3 subscribes to `Turbo::StreamsChannel "project:#{id}:onboarding"`.
6. `ImportProjectJob` loops issue pages, calls `EventMapper.upsert!`, broadcasts a row to `status_rows` per issue. Each new `Issue` triggers `SreInbox::Analyzer` (existing pipeline), which populates `sre_confidence`, `fix_diff`, `safe_to_auto_merge`. After analyzer completes, `AutoFix::OrchestratorJob` is enqueued.
7. `OrchestratorJob`:
   - exit if `Project.settings["github_installation_id"]` blank → mark `auto_fix_status = "awaiting_github"`
   - exit if `Issue.sre_analyzed_at` blank → mark `auto_fix_status = "awaiting_analysis"` (reconciled when analyzer completes)
   - exit if `project.auto_pr_confidence_threshold == 0` → return (manual-only mode; user can still click "Draft PR")
   - exit if `AutoPrEvent.where(project: p).where("opened_at > ?", 7.days.ago).count >= project.auto_pr_weekly_cap` → mark `queued_capped`
   - if `issue.sre_confidence < project.auto_pr_confidence_threshold` → mark `low_confidence`
   - else → enqueue `Github::PrCreationJob` (uses existing `issue.fix_diff` and `safe_to_auto_merge` flags)
8. `Github::PrCreationJob` opens PR via `Github::PrService` (existing); on success creates `AutoPrEvent`, marks `Issue.auto_fix_status = "pr_drafted"`, broadcasts a "PR drafted" row.
9. After import completes, `Sentry::Client.register_internal_integration` registers our webhook URL with Sentry for ongoing live events.

### Live ongoing flow

```
Sentry → POST /webhooks/sentry/:project_id (HMAC-SHA256 signed)
  → Sentry::WebhooksController verifies signature with project's sentry_webhook_secret
  → enqueue Sentry::IngestEventJob(payload)
  → IngestEventJob → EventMapper.upsert!
  → Issue after_create → AutoFix::OrchestratorJob (same flow)
```

### SDK path

1. User opens SDK card → install snippet revealed inline; `Project.create!` with no `sentry_*` settings.
2. Step 2 GitHub install (same as Sentry path).
3. Step 3 status: "Waiting for first event from your-app.com…"
4. First event arrives via existing `/api/v1/events` → `Issue` created → `OrchestratorJob` runs → status switches to "First event received! Drafting fixes…"

### Cap math (computed on read)

```ruby
AutoPrEvent.where(project: p).where("opened_at > ?", 7.days.ago).count
```

No counter column to keep in sync, no cron needed for resets. Index `(project_id, opened_at)` makes it cheap.

### Reconcilers

**Awaiting GitHub** — when `github_app#callback` fires, after saving `installation_id`:
```ruby
Issue.where(project: p, auto_fix_status: "awaiting_github").find_each do |i|
  AutoFix::OrchestratorJob.perform_later(i.id)
end
```

**Awaiting analysis** — `SreInbox::Analyzer` already runs as a job after issue creation; on completion it should call `AutoFix::OrchestratorJob.perform_later(issue.id)` if the issue has `auto_fix_status = "awaiting_analysis"` (or unconditionally — the orchestrator is idempotent and will re-evaluate gates).

## Routes

```ruby
# Add
get  "onboarding",                  to: "onboarding_wizard#show",         as: :onboarding
post "onboarding/source",           to: "onboarding_wizard#submit_source"
post "onboarding/sentry/verify",    to: "onboarding_wizard#verify_sentry_token"
post "onboarding/sentry/import",    to: "onboarding_wizard#start_sentry_import"
post "onboarding/complete",         to: "onboarding_wizard#complete"

post "webhooks/sentry/:project_id", to: "sentry/webhooks#receive",        as: :sentry_webhook

# Remove
get  "onboarding/welcome"           # → 301 redirect to /onboarding for any bookmarked links
get  "onboarding/new_project"
post "onboarding/create_project"
get  "onboarding/install_gem/:project_id"
post "onboarding/verify_gem/:project_id"
get  "onboarding/setup_github/:project_id"
post "onboarding/setup_github/:project_id"
```

## View structure

```
app/views/onboarding_wizard/
  show.html.erb                # shell: <turbo-frame id="wizard">
  _step_1_source.html.erb      # app name + 2 cards
  _step_1_sentry_form.html.erb # token paste, revealed in card
  _step_1_sentry_project_picker.html.erb
  _step_1_sdk_snippet.html.erb # gem install + DSN, revealed in card
  _step_2_github.html.erb      # one-click install button + skip link
  _step_3_status.html.erb      # streamed status feed
  _status_row.html.erb         # one row (kinds: issue_imported, pr_drafted, import_complete, error)
```

### Step decision logic (`#show`)

```ruby
def show
  @project = current_account.projects.order(:created_at).last
  @step = if @project.nil?                                            then 1
          elsif @project.settings["github_installation_id"].blank?    then 2
          else 3
          end
end
```

Refresh-safe; user can close the tab and resume from where they left off.

## Settings additions

`/projects/:id/settings` — new "Auto-fix" panel:

```
Weekly auto-PR cap:    [5 ▾]   (5 | 10 | 20)
Confidence threshold:  ( ) Off (0)   — never auto-PR (manual button only)
                       ( ) Medium (60)
                       (•) High (80)         [default]

Used in last 7 days: 3 / 5
[View auto-PR history]   ← links to filtered AutoPrEvent list
```

`/projects/:id/settings` — new "Sentry connection" panel (only shown if connected):

```
Connected to: my-org/backend (last sync: 2m ago)
[Re-import last 30 days]   [Disconnect Sentry]
```

## Edge cases & failure modes

| Case | Behavior |
|---|---|
| User cancels GitHub App install on github.com | Callback never fires; user lands back on Step 2 with the install button still showing. No partial state in DB. |
| Sentry token has no project access | `verify_token` succeeds but `list_projects` returns empty; inline error: *"This token has no project access — generate a new token with `project:read` scope."* |
| Sentry returns 429 during import | Sidekiq exponential-backoff retry; status feed shows *"Sentry rate-limited us, resuming in 30s…"* |
| User has 500+ historical Sentry issues | v1 caps import at last 7 days, max 100 issues. Status feed shows *"Imported 100 most recent issues from last 7 days"*. "Re-import last 30 days" in Settings raises the cap to 30 days, 500 issues. |
| AutoFix runs before GitHub connected | `Issue.auto_fix_status = "awaiting_github"`. Reconciler in `github_app#callback` re-enqueues all such issues for that project. |
| User reconnects Sentry to a different project | Old `sentry_*` settings overwritten; imported issues retained (they're real). Webhook secret rotated; old Sentry Internal Integration deregistered if possible. |
| Webhook arrives for deleted/disconnected project | 404, no enqueue. |
| Weekly cap hit mid-import | Issue marked `queued_capped`. `AutoFix::DrainQueueJob` (hourly cron) drains as the rolling window opens up. |
| Two webhooks for same Sentry issue arrive concurrently | `EventMapper.upsert!` keyed on `Issue.fingerprint`; idempotent. |
| GitHub PR creation fails (e.g., protected default branch) | No `AutoPrEvent` created (slot not burned); `Issue.auto_fix_status = "pr_failed"` with error details surfaced in inbox. |
| Multi-project account hits `/onboarding` after first signup | `before_action` redirects to `/inbox` if `current_account.projects.any?`. Adding additional projects later uses a slimmer "+ Add project" flow (out of v1 scope; existing add-project pages stay for now). |

## Security

- **Sentry token at rest**: ActiveRecord Encryption isn't fully wired in this codebase yet (see `app/models/uptime/monitor.rb:13` TODO — keys not in credentials). For v1, store in `Project.settings` JSONB. Open a follow-up issue to add `encrypts :sentry_auth_token` once AR Encryption keys are added; this design *does not* block on that, but the spec flags it explicitly.
- **Webhook signature**: HMAC-SHA256 of raw body using `project.settings["sentry_webhook_secret"]`. Constant-time compare via `ActiveSupport::SecurityUtils.secure_compare`. Reject if header missing or mismatched (401).
- **CSRF on webhook controller**: `skip_before_action :verify_authenticity_token` (same pattern as existing `github_app#webhook`).
- **Token scope check on verify**: warn user if token has more scopes than needed. Required: `project:read`, `event:read`, `org:read`.
- **PII in imported events**: Sentry payloads can contain user emails / IPs in `request.user`. Existing `Event` storage already handles error-tracking PII; no new exposure beyond what ActiveRabbit already accepts via its own SDK.

## Testing plan

### Unit
- `Sentry::Client` — VCR cassettes for `verify_token`, `list_projects`, `list_issues`, `register_internal_integration`. Cover 200, 401, 429, 5xx.
- `Sentry::EventMapper` — fixture-driven; assert `Issue` and `Event` rows match expected schema. Test fingerprint stability (same payload twice → upsert).
- `Sentry::ImportService` — stubbed `Client`; assert N issues created, N broadcasts emitted, `sentry_initial_import_completed_at` set.
- `AutoFix::OrchestratorJob` — table-driven: github not connected → awaiting_github; cap hit → queued_capped; threshold 0.0 → no-op; low confidence → low_confidence; high confidence → enqueues `Github::PrCreationJob`.
- `Sentry::WebhooksController` — signature valid / missing / mismatched; assert 401 path doesn't enqueue.

### Integration (system tests)
- Happy path Sentry: stub `Sentry::Client` with 3 fixture issues; click through wizard; assert Project created, ImportProjectJob enqueued, advances to Step 2; stub GitHub callback; lands on Step 3; `perform_enqueued_jobs`; assert 3 Issues + ≥1 AutoPrEvent.
- Happy path SDK: skip Sentry card; install GitHub; POST a fixture event to `/api/v1/events`; assert auto-PR job runs.
- Cap enforcement: pre-seed 5 `AutoPrEvent`s within last 7d; trigger 6th issue; assert `queued_capped` + no PR.
- Resume mid-flow: hit `/onboarding` after Project created but before GitHub installed; assert lands on Step 2.
- Skip-GitHub path: assert wizard advances; later install fires `awaiting_github` reconciler.
- Drain queue: pre-seed cap-hit issue + 5 AutoPrEvents (oldest 8 days old); run `DrainQueueJob`; assert oldest queued issue gets PR drafted.

### Contract
- Snapshot a real Sentry `issue.created` webhook payload + a real `list_issues` response. Re-snapshot when Sentry's API version changes.

### Manual verification
- Run wizard end-to-end in **Firefox** against a real Sentry sandbox project (per project preference). Confirm Turbo Stream broadcasts render in real time; GitHub App install round-trip lands user on Step 3.
- Trigger a real error from a sandbox Rails app via Sentry SDK; confirm webhook arrives and Issue appears in inbox within ~5s.

## Out of scope (v1)

- Replacing Sentry as the primary ingest (DSN proxy / Sentry-wire-protocol endpoint).
- Multi-project onboarding wizard (existing add-project flow stays for second-and-later projects).
- Auto-merging PRs without user review.
- AR Encryption for Sentry token (tracked as follow-up).
- "Repeat onboarding" / re-running the wizard for existing accounts.
- Bitbucket / GitLab support (GitHub-only for v1).

## Build sequence (rough)

1. Schema: `Project` columns, `auto_pr_events` table, `Issue.auto_fix_status`. Backfill defaults.
2. `Sentry::Client` + `Sentry::EventMapper` + `Sentry::ImportService` (with VCR-backed unit tests).
3. `AutoFix::OrchestratorJob` + `Github::PrCreationJob` extraction from `errors_controller#create_pr`.
4. `OnboardingWizardController` + Step 1 / Step 2 views (no Turbo Streams yet).
5. `Sentry::WebhooksController` + signature verification.
6. Step 3 status feed + Turbo Stream broadcasts wired into `ImportService` and `PrCreationJob`.
7. `AutoFix::DrainQueueJob` cron + `awaiting_github` reconciler.
8. Project Settings panels (Auto-fix, Sentry connection).
9. Delete legacy `OnboardingController` actions/views/routes; update `welcome` redirect.
10. End-to-end manual verification in Firefox against sandbox Sentry + GitHub.
