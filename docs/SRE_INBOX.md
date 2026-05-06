# SRE Inbox — architecture & data flow

End-to-end picture of how an error gets ingested, analyzed by the AI, and bucketed into one of the four inbox tabs at `/inbox`.

## Quick links

| What | Where |
|---|---|
| Inbox URL | `GET /inbox` (also `/`) |
| Controller | `app/controllers/sre_inbox_controller.rb` |
| View | `app/views/sre_inbox/index.html.erb` |
| Analyzer service | `app/services/sre_inbox/analyzer.rb` |
| LLM prompt | `app/prompts/sre_analyzer_prompt.rb` |
| Schema migration | `db/migrate/20260415000000_add_sre_analysis_columns_to_issues.rb` |
| Demo seed | `db/seeds/sre_inbox_demo.rb` |
| Tests | `test/integration/sre_inbox_controller_test.rb` (22 tests) |

## Tabs

| Tab | What it means | Source columns |
|---|---|---|
| **Needs review** | Human input required | `resolution_status='needs_attention'` OR PR in failed/review-needed state |
| **Agent working** | AI is mid-flight | `resolution_status='investigating'` OR PR being prepared / in CI |
| **Shipped** | Fix landed | PR `merged` OR `resolved` without a PR |
| **All errors** | No filter | every `Issue` for the current project |

Buckets are **mutually exclusive** — every issue lands in at most one of the first three (`Shipped > Needs review > Agent working`). "All errors" is the unfiltered view.

## ERD — tables and relationships

```
┌──────────────────────────────┐
│         accounts             │   (tenant root)
├──────────────────────────────┤
│ id                           │
│ name                         │
│ current_plan                 │
└──────────────┬───────────────┘
               │ 1
               │
               ▼ N
┌──────────────────────────────┐         ┌──────────────────────────────┐
│         projects             │ 1     N │           events             │
├──────────────────────────────┤────────▶├──────────────────────────────┤
│ id                           │         │ id                           │
│ account_id                   │         │ account_id, project_id       │
│ slug          (e.g. localhost│         │ issue_id  ─────────┐         │
│ name                         │         │ exception_class    │         │
│ tech_stack                   │         │ message            │         │
│ active                       │         │ backtrace          │         │
└──────────────┬───────────────┘         │ controller_action  │         │
               │ 1                       │ release_version    │         │
               │                         │ environment        │         │
               ▼ N                       │ occurred_at        │         │
┌────────────────────────────────────────┴────┐                         │
│                  issues                     │◀────────────────────────┘
├─────────────────────────────────────────────┤
│ id                                          │
│ account_id, project_id                      │
│ fingerprint  (sha of class+frame+action)    │
│ exception_class, top_frame, sample_message  │
│ controller_action, source (front/back)      │
│ status (open/wip/closed)                    │
│ severity (low/medium/high/critical)         │
│ count, first_seen_at, last_seen_at          │
│                                             │
│ ── written by SreInbox::Analyzer ───────    │
│ resolution_status                           │   investigating | needs_attention | resolved
│ sre_confidence (0-100)                      │
│ root_cause     (jsonb)                      │   {summary, explanation, triggered_by}
│ fix_diff       (text)                       │
│ safe_to_auto_merge (bool)                   │
│ sre_analyzed_at, sre_analysis (jsonb)       │
│                                             │
│ ── written by auto-fix PR pipeline ─────    │
│ auto_fix_status                             │   creating_pr | pr_created | pr_created_review_needed
│ auto_fix_pr_number, auto_fix_pr_url         │   ci_pending | ci_passed | ci_failed | ci_timeout
│ auto_fix_branch, auto_fix_attempted_at      │   merged | merge_failed | failed | monitor_error
│ auto_fix_merged_at, auto_fix_error          │
└─────────────────────────────────────────────┘
```

## Flow — input → analysis → inbox bucket

```
  CLIENT SDK                         API                              ASYNC JOBS
─────────────                  ───────────────                  ────────────────────────

POST /api/v1/                  EventsController#                ErrorIngestJob.perform_later
  events/errors  ────────────▶ create_error          ─────────▶  ├─ find_or_create_by_fingerprint
  events/batch                                                   │   → upsert Issue
  events                                                         │   → increment count, last_seen_at
                                                                 ├─ Event.create!(...)
                                                                 ├─ recompute severity (callback)
                                                                 └─ maybe enqueue AiSummaryJob
                                                                          │
                                                                          ▼
                                                          ┌──────────────────────────────────┐
                                                          │ SreInbox::Analyzer.new(issue).call│
                                                          ├──────────────────────────────────┤
                                                          │  build_payload                   │
                                                          │   ├─ stack trace, frequency      │
                                                          │   ├─ recent deploys, logs        │
                                                          │   ├─ similar issues, replays     │
                                                          │   └─ env, severity hint          │
                                                          │  invoke Claude API               │
                                                          │   (prompt: SreAnalyzerPrompt)    │
                                                          │  parse JSON                      │
                                                          │  persist! → updates Issue:       │
                                                          │   resolution_status              │
                                                          │   sre_confidence                 │
                                                          │   root_cause                     │
                                                          │   fix_diff                       │
                                                          │   safe_to_auto_merge             │
                                                          │   sre_analyzed_at                │
                                                          │   sre_analysis                   │
                                                          └──────────────┬───────────────────┘
                                                                         │
                                                                         ▼
                                                ┌─────────────────────────────────────────────┐
                                                │  Auto-fix PR pipeline (when safe & confident)│
                                                │                                              │
                                                │   creating_pr ─▶ pr_created ─▶ ci_pending    │
                                                │                       │              │       │
                                                │                       ▼              ▼       │
                                                │                pr_created_      ci_passed    │
                                                │                review_needed         │       │
                                                │                                      ▼       │
                                                │                                   merged     │
                                                │                                              │
                                                │   ✗ ci_failed / ci_timeout / merge_failed    │
                                                │     / failed / monitor_error                 │
                                                └────────────────────────┬─────────────────────┘
                                                                         │
                                                                         ▼
                              ╔══════════════════════════════════════════════════════════════╗
                              ║          GET /inbox  →  SreInboxController#index             ║
                              ╠══════════════════════════════════════════════════════════════╣
                              ║                                                              ║
                              ║   For each issue, classify (precedence top → bottom):        ║
                              ║                                                              ║
                              ║   1. SHIPPED                                                 ║
                              ║      auto_fix_status = 'merged'                              ║
                              ║      OR (resolution_status='resolved' AND auto_fix_status IS NULL) ║
                              ║                                                              ║
                              ║   2. NEEDS REVIEW   (= shipped excluded)                     ║
                              ║      resolution_status = 'needs_attention'                   ║
                              ║      OR auto_fix_status IN (pr_created_review_needed,        ║
                              ║                             ci_failed, ci_timeout,           ║
                              ║                             merge_failed, failed,            ║
                              ║                             monitor_error)                   ║
                              ║                                                              ║
                              ║   3. AGENT WORKING  (= shipped + needs_review excluded)      ║
                              ║      (resolution_status='investigating' AND no PR)           ║
                              ║      OR auto_fix_status IN (creating_pr, pr_created,         ║
                              ║                             ci_pending, ci_passed)           ║
                              ║                                                              ║
                              ║   4. ALL ERRORS — every issue (no filter)                    ║
                              ║                                                              ║
                              ╚══════════════════════════════════════════════════════════════╝
```

## How a single issue traverses the lifecycle

```
   Event arrives
        │
        ▼
   Issue created or count++         ─── status='open', resolution_status=NULL, auto_fix_status=NULL
        │                                ▼ appears only in "All errors"
        ▼
   SreInbox::Analyzer                ─── writes resolution_status + root_cause + fix_diff
        │
   ┌────┴──────────────┬──────────────────────┬──────────────────────────┐
   ▼                   ▼                      ▼                          ▼
investigating       needs_attention         resolved                  resolved
+ no PR             + no PR                 + no PR                   + auto_fix_status set
   │                   │                      │                          │
   ▼                   ▼                      ▼                          ▼
"Agent working"    "Needs review"           "Shipped"             starts PR pipeline
                                                                         │
                                            ┌───────────────────┬────────┴────────┬────────────┐
                                            ▼                   ▼                 ▼            ▼
                                        creating_pr ─▶     pr_created     pr_created_      ci_failed
                                        ci_pending         ci_passed      review_needed    merge_failed
                                            │                                  │                │
                                            ▼                                  ▼                ▼
                                       "Agent working"                    "Needs review"   "Needs review"
                                            │
                                            ▼
                                          merged
                                            │
                                            ▼
                                        "Shipped"
```

## Where each piece lives in the code

| Stage | File | Notes |
|---|---|---|
| HTTP ingest | `app/controllers/api/v1/events_controller.rb` | `create_error`, `create_batch` |
| Async ingest | `app/jobs/error_ingest_job.rb` | upserts `Issue`, creates `Event` |
| Fingerprint upsert | `app/models/issue.rb` `find_or_create_by_fingerprint` | atomic count++, reopens closed |
| Severity calc | `Issue#calculate_severity!` (before_save) | uses class + controller heuristics |
| AI analysis | `app/services/sre_inbox/analyzer.rb` | calls Claude (`claude-haiku-4-5`) |
| Prompt | `app/prompts/sre_analyzer_prompt.rb` | system + user message templates |
| Inbox bucketing | `app/controllers/sre_inbox_controller.rb` — `shipped_scope`, `needs_review_scope`, `agent_working_scope` | id-subquery exclusion → mutual exclusivity |
| Inbox UI | `app/views/sre_inbox/index.html.erb` | tabs + Linear-style chips |
| Routes | `config/routes.rb` | `root` and `/inbox` → `sre_inbox#index`; legacy paths 301 → `/inbox` |
| Tests | `test/integration/sre_inbox_controller_test.rb` | 22 tests covering buckets, exclusivity, redirects |

## Key invariants

- **Tenant scoping**: every `Issue`/`Event` row carries `account_id`; `acts_as_tenant` scopes queries to `current_account` automatically.
- **Fingerprint uniqueness**: `(project_id, fingerprint)` is unique — repeat errors update the same `Issue` row, they don't create new ones.
- **Bucket mutual exclusivity**: enforced in SQL via `where.not(id: <higher_priority_scope>.select(:id))`. Verified by the `mutual exclusivity` integration test.
- **PR-state alignment**: the view's `pr_state` helper and the controller's `*_PR_STATUSES` constants partition the same set — failed states display as red "closed" PR chips and live in the Needs review bucket.

## URL contract

| Path | Behavior |
|---|---|
| `/` | Renders the inbox (root) |
| `/inbox` | Canonical inbox URL |
| `/inbox?tab=shipped` | Filter to a specific tab (`needs_review` \| `agent_working` \| `shipped` \| `all`) |
| `/sre_inbox`, `/sre_inbox2` | 301 → `/inbox` (preserves query string) |
| `/:project_slug/sre_inbox`, `/:project_slug/sre_inbox2` | 301 → `/inbox` (stashes slug into session/cookie first) |

## Constants — the partition

In `SreInboxController`:

```ruby
SHIPPED_PR_STATUSES       = %w[merged]
NEEDS_REVIEW_PR_STATUSES  = %w[pr_created_review_needed ci_failed ci_timeout
                                merge_failed failed monitor_error]
AGENT_WORKING_PR_STATUSES = %w[creating_pr pr_created ci_pending ci_passed]
```

These three sets cover the full `Issue::AUTO_FIX_STATUSES` enum without overlap.

## Running the demo

```bash
bin/rails runner db/seeds/sre_inbox_demo.rb   # seeds 8 fixture issues per project
bin/rails server
# visit http://localhost:3003/inbox
```

## Running the tests

```bash
bin/rails test test/integration/sre_inbox_controller_test.rb
# 22 runs, 44 assertions, 0 failures
```
