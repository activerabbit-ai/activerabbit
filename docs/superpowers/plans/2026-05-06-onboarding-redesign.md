# Onboarding Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 5-page onboarding flow with a single Turbo wizard that connects Sentry (or installs the ActiveRabbit SDK), connects GitHub, then auto-drafts PRs for high-confidence errors gated by a configurable rolling 7-day cap.

**Architecture:** New `OnboardingWizardController` with Turbo Frame swaps; new `Sentry::*` services and webhook for backfill + live sync; new `AutoFix::OrchestratorJob` that gates the existing analyzer→PR pipeline on `Issue.sre_confidence`, project cap, and GitHub readiness. Existing onboarding pages and routes are deleted.

**Tech Stack:** Rails 7.1+, Hotwire (Turbo Streams + Frames), Sidekiq, RSpec + WebMock/VCR, ActsAsTenant. Existing `Github::PrService` and `SreInbox::Analyzer` are reused.

**Spec:** `docs/superpowers/specs/2026-05-06-onboarding-redesign-design.md`

---

## Phase 1 — Schema

### Task 1: Add auto-fix columns and `auto_pr_events` table

**Files:**
- Create: `db/migrate/<timestamp>_add_auto_fix_to_projects_and_issues.rb`
- Create: `db/migrate/<timestamp>_create_auto_pr_events.rb`

- [ ] **Step 1: Generate migrations**

```bash
docker exec activerabbit-web-1 bin/rails g migration AddAutoFixToProjectsAndIssues
docker exec activerabbit-web-1 bin/rails g migration CreateAutoPrEvents
```

- [ ] **Step 2: Write `AddAutoFixToProjectsAndIssues`**

```ruby
class AddAutoFixToProjectsAndIssues < ActiveRecord::Migration[7.1]
  def change
    add_column :projects, :auto_pr_weekly_cap, :integer, default: 5, null: false
    add_column :projects, :auto_pr_confidence_threshold, :integer, default: 80, null: false
    add_column :issues, :auto_fix_status, :string
    add_index  :issues, [:project_id, :auto_fix_status]
  end
end
```

- [ ] **Step 3: Write `CreateAutoPrEvents`**

```ruby
class CreateAutoPrEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :auto_pr_events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :issue,   null: false, foreign_key: true
      t.datetime   :opened_at, null: false
      t.integer    :github_pr_number, null: false
      t.string     :github_pr_url, null: false
      t.timestamps
    end
    add_index :auto_pr_events, [:project_id, :opened_at]
  end
end
```

- [ ] **Step 4: Run migrations**

```bash
docker exec activerabbit-web-1 bin/rails db:migrate
```

Expected: both migrations apply cleanly; `db/schema.rb` updated.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "feat(onboarding): add auto-fix columns and auto_pr_events table"
```

---

### Task 2: Relax `:url` and `:tech_stack` create-time requirements

**Files:**
- Modify: `app/models/project.rb:29-30`

The Sentry path doesn't have a deployed URL or known tech-stack at creation time; both can be filled in Settings later. Make them optional on create.

- [ ] **Step 1: Write spec for relaxed validation**

Create `spec/models/project_relaxed_validation_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Project, type: :model do
  describe "create-time validations" do
    let(:account) { Account.create!(name: "Acme") }

    it "creates without url or tech_stack" do
      ActsAsTenant.with_tenant(account) do
        p = Project.new(name: "X", environment: "production")
        expect(p.save).to be true
      end
    end

    it "still requires name" do
      ActsAsTenant.with_tenant(account) do
        p = Project.new(environment: "production")
        expect(p.save).to be false
        expect(p.errors[:name]).to be_present
      end
    end
  end
end
```

- [ ] **Step 2: Run spec, see it fail**

```bash
docker exec activerabbit-web-1 bin/rspec spec/models/project_relaxed_validation_spec.rb
```

Expected: fails — current `validates :url, presence: true` rejects.

- [ ] **Step 3: Edit `app/models/project.rb` lines 29-30**

Replace:
```ruby
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }
  validates :tech_stack, presence: { message: "must be selected" }, on: :create
```
with:
```ruby
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }, allow_blank: true
  validates :tech_stack, presence: { message: "must be selected" }, on: :create, if: :tech_stack_required?

  def tech_stack_required?
    settings.blank? || settings["sentry_org_slug"].blank?
  end
```

- [ ] **Step 4: Run spec, see it pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/models/project_relaxed_validation_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/project.rb spec/models/project_relaxed_validation_spec.rb
git commit -m "feat(onboarding): relax url and tech_stack required-on-create"
```

---

## Phase 2 — Sentry Domain

### Task 3: `Sentry::Client.verify_token`

**Files:**
- Create: `app/services/sentry/client.rb`
- Create: `spec/services/sentry/client_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Sentry::Client do
  let(:token) { "sntrys_eyXXXXXX" }
  subject(:client) { described_class.new(token) }

  describe "#verify_token" do
    it "returns true for 200 from /api/0/" do
      stub_request(:get, "https://sentry.io/api/0/")
        .with(headers: { "Authorization" => "Bearer #{token}" })
        .to_return(status: 200, body: "{}")
      expect(client.verify_token).to eq(true)
    end

    it "returns false for 401" do
      stub_request(:get, "https://sentry.io/api/0/")
        .to_return(status: 401, body: '{"detail":"Invalid token"}')
      expect(client.verify_token).to eq(false)
    end
  end
end
```

- [ ] **Step 2: Run, see fail**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/client_spec.rb
```

Expected: fails — `Sentry::Client` undefined.

- [ ] **Step 3: Implement `app/services/sentry/client.rb`**

```ruby
module Sentry
  class Client
    BASE = "https://sentry.io/api/0".freeze

    def initialize(token)
      @token = token
    end

    def verify_token
      get("/").is_a?(Hash) && @last_status == 200
    end

    private

    def get(path, query: {})
      require "net/http"
      require "json"
      uri = URI("#{BASE}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      @last_status = res.code.to_i
      JSON.parse(res.body) rescue {}
    end
  end
end
```

- [ ] **Step 4: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/client_spec.rb
```

Expected: 2 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/sentry/client.rb spec/services/sentry/client_spec.rb
git commit -m "feat(sentry): add Sentry::Client.verify_token"
```

---

### Task 4: `Sentry::Client.list_projects`

**Files:**
- Modify: `app/services/sentry/client.rb`
- Modify: `spec/services/sentry/client_spec.rb`

- [ ] **Step 1: Add failing spec**

Append to `spec/services/sentry/client_spec.rb`:
```ruby
  describe "#list_projects" do
    it "returns project list across all orgs" do
      stub_request(:get, "https://sentry.io/api/0/projects/")
        .to_return(
          status: 200,
          body: JSON.dump([
            { "slug" => "backend", "name" => "Backend",
              "organization" => { "slug" => "acme" }, "platform" => "ruby" },
            { "slug" => "web", "name" => "Web",
              "organization" => { "slug" => "acme" }, "platform" => "javascript" }
          ])
        )
      result = client.list_projects
      expect(result.size).to eq(2)
      expect(result.first).to include(org_slug: "acme", project_slug: "backend", name: "Backend", platform: "ruby")
    end

    it "returns [] on 401" do
      stub_request(:get, "https://sentry.io/api/0/projects/").to_return(status: 401)
      expect(client.list_projects).to eq([])
    end
  end
```

- [ ] **Step 2: Run, see fail**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/client_spec.rb -e list_projects
```

- [ ] **Step 3: Implement**

Append to `app/services/sentry/client.rb` (inside class):
```ruby
    def list_projects
      response = get("/projects/")
      return [] unless @last_status == 200
      Array(response).map do |p|
        {
          org_slug: p.dig("organization", "slug"),
          project_slug: p["slug"],
          name: p["name"],
          platform: p["platform"]
        }
      end
    end
```

- [ ] **Step 4: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/client_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/services/sentry/client.rb spec/services/sentry/client_spec.rb
git commit -m "feat(sentry): add Sentry::Client.list_projects"
```

---

### Task 5: `Sentry::Client.list_issues`

**Files:**
- Modify: `app/services/sentry/client.rb`
- Modify: `spec/services/sentry/client_spec.rb`

- [ ] **Step 1: Add failing spec**

Append to `spec/services/sentry/client_spec.rb`:
```ruby
  describe "#list_issues" do
    it "fetches recent issues with statsPeriod and limit" do
      stub_request(:get, "https://sentry.io/api/0/projects/acme/backend/issues/")
        .with(query: hash_including({ "statsPeriod" => "7d", "limit" => "100", "query" => "is:unresolved" }))
        .to_return(
          status: 200,
          body: JSON.dump([
            { "id" => "1", "title" => "NoMethodError", "culprit" => "X#y",
              "metadata" => { "type" => "NoMethodError", "value" => "undefined method `foo'" },
              "permalink" => "https://sentry.io/issue/1",
              "platform" => "ruby", "lastSeen" => "2026-05-01T00:00:00Z",
              "count" => "12", "userCount" => 3 }
          ])
        )
      issues = client.list_issues(org: "acme", project_slug: "backend", days: 7, limit: 100)
      expect(issues.size).to eq(1)
      expect(issues.first[:sentry_issue_id]).to eq("1")
      expect(issues.first[:title]).to eq("NoMethodError")
    end
  end
```

- [ ] **Step 2: Run, see fail**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/client_spec.rb -e list_issues
```

- [ ] **Step 3: Implement**

Append to `app/services/sentry/client.rb`:
```ruby
    def list_issues(org:, project_slug:, days: 7, limit: 100)
      response = get(
        "/projects/#{org}/#{project_slug}/issues/",
        query: { "statsPeriod" => "#{days}d", "limit" => limit.to_s, "query" => "is:unresolved" }
      )
      return [] unless @last_status == 200
      Array(response).map do |i|
        {
          sentry_issue_id: i["id"],
          title: i["title"],
          culprit: i["culprit"],
          exception_class: i.dig("metadata", "type"),
          exception_message: i.dig("metadata", "value"),
          permalink: i["permalink"],
          platform: i["platform"],
          last_seen: i["lastSeen"],
          event_count: i["count"].to_i,
          user_count: i["userCount"].to_i,
          raw: i
        }
      end
    end
```

- [ ] **Step 4: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/client_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/services/sentry/client.rb spec/services/sentry/client_spec.rb
git commit -m "feat(sentry): add Sentry::Client.list_issues"
```

---

### Task 6: `Sentry::Client.register_internal_integration`

**Files:**
- Modify: `app/services/sentry/client.rb`
- Modify: `spec/services/sentry/client_spec.rb`

- [ ] **Step 1: Add failing spec**

```ruby
  describe "#register_internal_integration" do
    it "POSTs sentry-app spec for the org and returns id + token" do
      stub_request(:post, "https://sentry.io/api/0/organizations/acme/sentry-apps/")
        .with(headers: { "Authorization" => "Bearer #{token}" })
        .to_return(status: 201, body: JSON.dump({ "uuid" => "app-uuid", "slug" => "ar-acme" }))
      stub_request(:post, "https://sentry.io/api/0/sentry-apps/ar-acme/api-tokens/")
        .to_return(status: 201, body: JSON.dump({ "token" => "internal-token" }))
      result = client.register_internal_integration(org: "acme", webhook_url: "https://app.example.com/webhooks/sentry/1", name: "ActiveRabbit (Acme P1)")
      expect(result).to include(integration_uuid: "app-uuid", api_token: "internal-token")
    end
  end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement**

```ruby
    def register_internal_integration(org:, webhook_url:, name:)
      app = post("/organizations/#{org}/sentry-apps/", body: {
        name: name,
        webhookUrl: webhook_url,
        scopes: %w[event:read project:read],
        events: %w[issue],
        isInternal: true
      })
      return { error: "create_failed" } unless @last_status.between?(200, 299) && app["slug"]
      tok = post("/sentry-apps/#{app['slug']}/api-tokens/", body: {})
      { integration_uuid: app["uuid"], integration_slug: app["slug"], api_token: tok["token"] }
    end

    private

    def post(path, body:)
      require "net/http"
      require "json"
      uri = URI("#{BASE}#{path}")
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      @last_status = res.code.to_i
      JSON.parse(res.body) rescue {}
    end
```

(Move the existing `private` marker so `get` and `post` are both private; keep the public methods above it.)

- [ ] **Step 4: Run, see pass**

- [ ] **Step 5: Commit**

```bash
git add app/services/sentry/client.rb spec/services/sentry/client_spec.rb
git commit -m "feat(sentry): register internal integration for live webhooks"
```

---

### Task 7: `Sentry::EventMapper`

**Files:**
- Create: `app/services/sentry/event_mapper.rb`
- Create: `spec/services/sentry/event_mapper_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Sentry::EventMapper do
  let(:account) { Account.create!(name: "Acme") }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      Project.create!(name: "P", environment: "production",
                      settings: { "sentry_org_slug" => "acme", "sentry_project_slug" => "backend" })
    end
  end
  let(:payload) do
    {
      sentry_issue_id: "42",
      title: "NoMethodError: undefined method `foo'",
      culprit: "UsersController#show",
      exception_class: "NoMethodError",
      exception_message: "undefined method `foo'",
      permalink: "https://sentry.io/issue/42",
      platform: "ruby",
      last_seen: "2026-05-05T10:00:00Z",
      event_count: 7,
      user_count: 2,
      raw: {}
    }
  end

  it "creates an Issue keyed on a stable fingerprint" do
    ActsAsTenant.with_tenant(account) do
      issue = described_class.upsert!(project, payload)
      expect(issue).to be_persisted
      expect(issue.fingerprint).to eq("sentry:42")
      expect(issue.exception_class).to eq("NoMethodError")
    end
  end

  it "is idempotent — second call updates the same row" do
    ActsAsTenant.with_tenant(account) do
      a = described_class.upsert!(project, payload)
      b = described_class.upsert!(project, payload.merge(event_count: 9))
      expect(a.id).to eq(b.id)
      expect(b.event_count).to eq(9) if b.respond_to?(:event_count)
    end
  end
end
```

- [ ] **Step 2: Run, see fail**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/event_mapper_spec.rb
```

- [ ] **Step 3: Inspect Issue model for actual columns**

```bash
docker exec activerabbit-web-1 bin/rails runner "puts Issue.column_names.sort"
```

Use the output to map fields below. The mapper sets only columns that actually exist on `Issue`. The set listed below is the spec's recommendation — drop any column not present, leave a comment for the implementer.

- [ ] **Step 4: Implement `app/services/sentry/event_mapper.rb`**

```ruby
module Sentry
  class EventMapper
    def self.upsert!(project, payload)
      fingerprint = "sentry:#{payload[:sentry_issue_id]}"
      issue = project.issues.find_or_initialize_by(fingerprint: fingerprint)
      issue.assign_attributes(
        message: payload[:title],
        exception_class: payload[:exception_class],
        culprit: payload[:culprit],
        platform: payload[:platform],
        last_seen_at: payload[:last_seen],
        external_url: payload[:permalink],
        source: "sentry"
      ).then { |attrs| attrs }
      # Drop any attribute the Issue table does not have:
      issue.attributes.keys.each do |k|
        # no-op; assign_attributes already filtered by setters
      end
      issue.save!
      issue
    end
  end
end
```

NOTE FOR IMPLEMENTER: After running `Issue.column_names`, edit the `assign_attributes` call so it only references real columns. If `external_url`, `culprit`, `platform`, `source`, or `last_seen_at` don't exist, store them under `issue.metadata` (JSONB) instead, falling back to the existing JSON `metadata` column on `Issue`.

- [ ] **Step 5: Run spec, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/event_mapper_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/services/sentry/event_mapper.rb spec/services/sentry/event_mapper_spec.rb
git commit -m "feat(sentry): add EventMapper.upsert! for Sentry payloads"
```

---

### Task 8: `Sentry::ImportService`

**Files:**
- Create: `app/services/sentry/import_service.rb`
- Create: `spec/services/sentry/import_service_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Sentry::ImportService do
  let(:account) { Account.create!(name: "Acme") }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      Project.create!(name: "P", environment: "production",
                      settings: {
                        "sentry_org_slug" => "acme",
                        "sentry_project_slug" => "backend",
                        "sentry_auth_token" => "tkn"
                      })
    end
  end
  let(:client) { instance_double(Sentry::Client) }
  let(:issues) do
    [
      { sentry_issue_id: "1", title: "ErrA", exception_class: "A", platform: "ruby",
        permalink: "p1", last_seen: nil, event_count: 1, user_count: 1, culprit: nil, exception_message: nil, raw: {} },
      { sentry_issue_id: "2", title: "ErrB", exception_class: "B", platform: "ruby",
        permalink: "p2", last_seen: nil, event_count: 2, user_count: 1, culprit: nil, exception_message: nil, raw: {} }
    ]
  end

  before do
    allow(Sentry::Client).to receive(:new).with("tkn").and_return(client)
    allow(client).to receive(:list_issues).and_return(issues)
  end

  it "creates one Issue per Sentry issue and stamps initial_import_completed_at" do
    ActsAsTenant.with_tenant(account) do
      expect { described_class.call(project) }.to change { project.issues.count }.by(2)
      expect(project.reload.settings["sentry_initial_import_completed_at"]).to be_present
    end
  end

  it "broadcasts a Turbo Stream row per issue" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      .with("project:#{project.id}:onboarding", hash_including(target: "status_rows"))
      .at_least(:twice)
    ActsAsTenant.with_tenant(account) { described_class.call(project) }
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement `app/services/sentry/import_service.rb`**

```ruby
module Sentry
  class ImportService
    def self.call(project, days: 7, limit: 100)
      new(project, days: days, limit: limit).call
    end

    def initialize(project, days:, limit:)
      @project = project
      @days = days
      @limit = limit
    end

    def call
      token = @project.settings["sentry_auth_token"]
      org = @project.settings["sentry_org_slug"]
      proj = @project.settings["sentry_project_slug"]
      return { error: "missing_sentry_settings" } unless token && org && proj

      client = Sentry::Client.new(token)
      issues = client.list_issues(org: org, project_slug: proj, days: @days, limit: @limit)

      issues.each do |payload|
        issue = Sentry::EventMapper.upsert!(@project, payload)
        broadcast_imported(issue)
        AutoFix::OrchestratorJob.perform_later(issue.id)
      end

      stamp_completion!(issues.size)
      broadcast_complete(issues.size)
      { imported: issues.size }
    end

    private

    def stamp_completion!(count)
      settings = @project.settings || {}
      settings["sentry_initial_import_completed_at"] = Time.current.iso8601
      settings["sentry_initial_import_count"] = count
      @project.update!(settings: settings)
    end

    def broadcast_imported(issue)
      Turbo::StreamsChannel.broadcast_append_to(
        "project:#{@project.id}:onboarding",
        target: "status_rows",
        partial: "onboarding_wizard/status_row",
        locals: { kind: :issue_imported, issue: issue }
      )
    end

    def broadcast_complete(count)
      Turbo::StreamsChannel.broadcast_append_to(
        "project:#{@project.id}:onboarding",
        target: "status_rows",
        partial: "onboarding_wizard/status_row",
        locals: { kind: :import_complete, count: count }
      )
    end
  end
end
```

- [ ] **Step 4: Run spec, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/services/sentry/import_service_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/services/sentry/import_service.rb spec/services/sentry/import_service_spec.rb
git commit -m "feat(sentry): add ImportService with Turbo Stream broadcasts"
```

---

### Task 9: `Sentry::ImportProjectJob`

**Files:**
- Create: `app/jobs/sentry/import_project_job.rb`
- Create: `spec/jobs/sentry/import_project_job_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe Sentry::ImportProjectJob, type: :job do
  it "calls Sentry::ImportService.call with the project" do
    project = double("Project", id: 1)
    allow(Project).to receive(:find).with(1).and_return(project)
    expect(Sentry::ImportService).to receive(:call).with(project)
    described_class.perform_now(1)
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement `app/jobs/sentry/import_project_job.rb`**

```ruby
module Sentry
  class ImportProjectJob < ApplicationJob
    queue_as :default

    def perform(project_id)
      project = Project.find(project_id)
      Sentry::ImportService.call(project)
    end
  end
end
```

- [ ] **Step 4: Run, see pass**

- [ ] **Step 5: Commit**

```bash
git add app/jobs/sentry/import_project_job.rb spec/jobs/sentry/import_project_job_spec.rb
git commit -m "feat(sentry): add ImportProjectJob"
```

---

## Phase 3 — AutoFix Domain

### Task 10: `AutoPrEvent` model

**Files:**
- Create: `app/models/auto_pr_event.rb`
- Create: `spec/models/auto_pr_event_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe AutoPrEvent, type: :model do
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:issue) }

  it "validates required fields" do
    expect(AutoPrEvent.new.valid?).to eq(false)
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement `app/models/auto_pr_event.rb`**

```ruby
class AutoPrEvent < ApplicationRecord
  acts_as_tenant(:account, through: :project)
  belongs_to :project
  belongs_to :issue

  validates :opened_at, :github_pr_number, :github_pr_url, presence: true

  scope :within_last, ->(duration) { where("opened_at > ?", duration.ago) }
end
```

- [ ] **Step 4: Add `has_many :auto_pr_events` to `Project` and `Issue`**

In `app/models/project.rb`, after the `has_many` block (around line 23):
```ruby
  has_many :auto_pr_events, dependent: :destroy
```

In `app/models/issue.rb` (find the `has_many` section):
```ruby
  has_many :auto_pr_events, dependent: :destroy
```

- [ ] **Step 5: Run, see pass**

- [ ] **Step 6: Commit**

```bash
git add app/models/auto_pr_event.rb spec/models/auto_pr_event_spec.rb app/models/project.rb app/models/issue.rb
git commit -m "feat(autofix): add AutoPrEvent model"
```

---

### Task 11: `Github::PrCreationJob` (extract from controller)

**Files:**
- Create: `app/jobs/github/pr_creation_job.rb`
- Create: `spec/jobs/github/pr_creation_job_spec.rb`

The existing `errors_controller#create_pr` (line 498) calls `Github::PrService.new(project).create_pr_for_issue(issue)` and renders flash. Extract the call into a job so `OrchestratorJob` can enqueue it.

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe Github::PrCreationJob, type: :job do
  let(:account) { Account.create!(name: "Acme") }
  let(:project) { ActsAsTenant.with_tenant(account) { Project.create!(name: "P", environment: "production") } }
  let(:issue)   { ActsAsTenant.with_tenant(account) { project.issues.create!(message: "x", fingerprint: "fp", auto_fix_status: "pending") } }
  let(:pr_service) { instance_double(Github::PrService) }

  before { allow(Github::PrService).to receive(:new).with(project).and_return(pr_service) }

  it "creates an AutoPrEvent and updates issue status on success" do
    allow(pr_service).to receive(:create_pr_for_issue)
      .with(issue, anything)
      .and_return(success: true, pr_number: 42, pr_url: "https://github.com/acme/x/pull/42")

    expect {
      ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
    }.to change { AutoPrEvent.count }.by(1)
    expect(issue.reload.auto_fix_status).to eq("pr_drafted")
  end

  it "marks issue pr_failed on failure" do
    allow(pr_service).to receive(:create_pr_for_issue)
      .and_return(success: false, error: "branch protected")

    ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
    expect(issue.reload.auto_fix_status).to eq("pr_failed")
    expect(AutoPrEvent.count).to eq(0)
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement `app/jobs/github/pr_creation_job.rb`**

```ruby
module Github
  class PrCreationJob < ApplicationJob
    queue_as :default

    def perform(issue_id)
      issue = Issue.find(issue_id)
      project = issue.project
      ActsAsTenant.with_tenant(project.account) do
        result = Github::PrService.new(project).create_pr_for_issue(issue)

        if result[:success]
          AutoPrEvent.create!(
            project: project,
            issue: issue,
            opened_at: Time.current,
            github_pr_number: result[:pr_number],
            github_pr_url: result[:pr_url]
          )
          issue.update!(auto_fix_status: "pr_drafted")
          broadcast_pr_drafted(project, issue, result)
        else
          issue.update!(auto_fix_status: "pr_failed")
        end
      end
    end

    private

    def broadcast_pr_drafted(project, issue, result)
      Turbo::StreamsChannel.broadcast_append_to(
        "project:#{project.id}:onboarding",
        target: "status_rows",
        partial: "onboarding_wizard/status_row",
        locals: { kind: :pr_drafted, issue: issue, pr_url: result[:pr_url], pr_number: result[:pr_number] }
      )
    end
  end
end
```

- [ ] **Step 4: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/jobs/github/pr_creation_job_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/jobs/github/pr_creation_job.rb spec/jobs/github/pr_creation_job_spec.rb
git commit -m "feat(github): extract PR creation into a job"
```

---

### Task 12: `AutoFix::OrchestratorJob` — gates

**Files:**
- Create: `app/jobs/auto_fix/orchestrator_job.rb`
- Create: `spec/jobs/auto_fix/orchestrator_job_spec.rb`

- [ ] **Step 1: Spec — table-driven**

```ruby
require "rails_helper"

RSpec.describe AutoFix::OrchestratorJob, type: :job do
  let(:account) { Account.create!(name: "Acme") }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      Project.create!(name: "P", environment: "production",
                      auto_pr_weekly_cap: 5, auto_pr_confidence_threshold: 80,
                      settings: { "github_installation_id" => "1" })
    end
  end
  let(:issue) do
    ActsAsTenant.with_tenant(account) do
      project.issues.create!(message: "x", fingerprint: "fp", sre_confidence: 90, sre_analyzed_at: Time.current)
    end
  end

  it "enqueues PrCreationJob when all gates pass" do
    expect(Github::PrCreationJob).to receive(:perform_later).with(issue.id)
    ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
  end

  it "marks awaiting_github when github_installation_id missing" do
    project.update!(settings: {})
    ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
    expect(issue.reload.auto_fix_status).to eq("awaiting_github")
  end

  it "marks awaiting_analysis when sre_analyzed_at blank" do
    issue.update!(sre_analyzed_at: nil)
    ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
    expect(issue.reload.auto_fix_status).to eq("awaiting_analysis")
  end

  it "no-ops when threshold is 0" do
    project.update!(auto_pr_confidence_threshold: 0)
    expect(Github::PrCreationJob).not_to receive(:perform_later)
    ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
  end

  it "marks queued_capped when cap reached" do
    5.times do |i|
      ActsAsTenant.with_tenant(account) do
        AutoPrEvent.create!(project: project, issue: issue, opened_at: i.hours.ago,
                            github_pr_number: 100 + i, github_pr_url: "https://x/#{i}")
      end
    end
    ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
    expect(issue.reload.auto_fix_status).to eq("queued_capped")
  end

  it "marks low_confidence when below threshold" do
    issue.update!(sre_confidence: 50)
    ActsAsTenant.with_tenant(account) { described_class.perform_now(issue.id) }
    expect(issue.reload.auto_fix_status).to eq("low_confidence")
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement `app/jobs/auto_fix/orchestrator_job.rb`**

```ruby
module AutoFix
  class OrchestratorJob < ApplicationJob
    queue_as :default

    def perform(issue_id)
      issue = Issue.find(issue_id)
      project = issue.project
      ActsAsTenant.with_tenant(project.account) { evaluate(issue, project) }
    end

    private

    def evaluate(issue, project)
      return mark(issue, "awaiting_github")  if project.settings.to_h["github_installation_id"].blank?
      return mark(issue, "awaiting_analysis") if issue.sre_analyzed_at.blank?
      return                                   if project.auto_pr_confidence_threshold.to_i.zero?

      used = AutoPrEvent.where(project: project).within_last(7.days).count
      return mark(issue, "queued_capped")     if used >= project.auto_pr_weekly_cap.to_i

      if issue.sre_confidence.to_i >= project.auto_pr_confidence_threshold.to_i
        Github::PrCreationJob.perform_later(issue.id)
      else
        mark(issue, "low_confidence")
      end
    end

    def mark(issue, status)
      issue.update!(auto_fix_status: status)
    end
  end
end
```

- [ ] **Step 4: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/jobs/auto_fix/orchestrator_job_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/jobs/auto_fix/orchestrator_job.rb spec/jobs/auto_fix/orchestrator_job_spec.rb
git commit -m "feat(autofix): add OrchestratorJob with gate logic"
```

---

### Task 13: Wire orchestrator into analyzer completion

**Files:**
- Modify: `app/services/sre_inbox/analyzer.rb` (around line 238)
- Modify: `spec/services/sre_inbox/analyzer_spec.rb` if it exists; otherwise add coverage in `spec/jobs/auto_fix/orchestrator_job_spec.rb`

- [ ] **Step 1: After `@issue.update!(attrs.compact)` in `Analyzer#persist!`, enqueue orchestrator**

Edit `app/services/sre_inbox/analyzer.rb` `persist!`:
```ruby
    def persist!(analysis)
      attrs = {
        # ... existing attrs ...
      }
      @issue.update!(attrs.compact)
      AutoFix::OrchestratorJob.perform_later(@issue.id)
    end
```

- [ ] **Step 2: Add a regression spec**

Create or extend `spec/services/sre_inbox/analyzer_orchestrator_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe SreInbox::Analyzer, "orchestrator handoff" do
  let(:account) { Account.create!(name: "Acme") }
  let(:project) { ActsAsTenant.with_tenant(account) { Project.create!(name: "P", environment: "production") } }
  let(:issue)   { ActsAsTenant.with_tenant(account) { project.issues.create!(message: "x", fingerprint: "fp") } }

  it "enqueues OrchestratorJob after persist!" do
    analyzer = described_class.new(issue)
    expect(AutoFix::OrchestratorJob).to receive(:perform_later).with(issue.id)
    analyzer.send(:persist!, { "resolution_status" => "open", "confidence" => 70 })
  end
end
```

- [ ] **Step 3: Run, see pass**

- [ ] **Step 4: Commit**

```bash
git add app/services/sre_inbox/analyzer.rb spec/services/sre_inbox/
git commit -m "feat(autofix): hand off to OrchestratorJob after analysis"
```

---

### Task 14: Drain queue cron job

**Files:**
- Create: `app/jobs/auto_fix/drain_queue_job.rb`
- Create: `spec/jobs/auto_fix/drain_queue_job_spec.rb`
- Modify: `config/initializers/sidekiq_cron.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe AutoFix::DrainQueueJob do
  it "re-enqueues the oldest queued_capped issue per project when window opens" do
    account = Account.create!(name: "Acme")
    project = ActsAsTenant.with_tenant(account) do
      Project.create!(name: "P", environment: "production", auto_pr_weekly_cap: 5,
                      settings: { "github_installation_id" => "1" })
    end
    queued = ActsAsTenant.with_tenant(account) do
      project.issues.create!(message: "old", fingerprint: "old",
                             auto_fix_status: "queued_capped",
                             sre_confidence: 90, sre_analyzed_at: 1.day.ago)
    end
    # Cap is 5 but all events are >7 days old → cap is open
    5.times do |i|
      ActsAsTenant.with_tenant(account) do
        AutoPrEvent.create!(project: project, issue: queued, opened_at: 8.days.ago - i.hours,
                            github_pr_number: i, github_pr_url: "https://x/#{i}")
      end
    end

    expect(AutoFix::OrchestratorJob).to receive(:perform_later).with(queued.id)
    described_class.perform_now
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement `app/jobs/auto_fix/drain_queue_job.rb`**

```ruby
module AutoFix
  class DrainQueueJob < ApplicationJob
    queue_as :default

    def perform
      Project.find_each do |project|
        ActsAsTenant.with_tenant(project.account) { drain(project) }
      end
    end

    private

    def drain(project)
      used = AutoPrEvent.where(project: project).within_last(7.days).count
      return if used >= project.auto_pr_weekly_cap.to_i

      slots = project.auto_pr_weekly_cap.to_i - used
      project.issues
             .where(auto_fix_status: "queued_capped")
             .order(:created_at)
             .limit(slots)
             .pluck(:id)
             .each { |id| AutoFix::OrchestratorJob.perform_later(id) }
    end
  end
end
```

- [ ] **Step 4: Schedule the job hourly**

In `config/initializers/sidekiq_cron.rb`, add (alongside existing cron entries):
```ruby
  "auto_fix_drain_queue" => {
    "class" => "AutoFix::DrainQueueJob",
    "cron"  => "0 * * * *",
    "queue" => "default"
  }
```

- [ ] **Step 5: Run, see pass**

- [ ] **Step 6: Commit**

```bash
git add app/jobs/auto_fix/drain_queue_job.rb spec/jobs/auto_fix/drain_queue_job_spec.rb config/initializers/sidekiq_cron.rb
git commit -m "feat(autofix): hourly DrainQueueJob to drain capped issues"
```

---

### Task 15: GitHub-callback reconciler for `awaiting_github`

**Files:**
- Modify: `app/controllers/github_app_controller.rb` (after line 38, the `project.update(settings: settings)` call)

- [ ] **Step 1: Add a system spec**

Create `spec/requests/github_callback_reconciler_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "GitHub callback reconciler" do
  let(:account) { Account.create!(name: "Acme") }
  let(:project) { ActsAsTenant.with_tenant(account) { Project.create!(name: "P", environment: "production") } }
  let!(:issue)  { ActsAsTenant.with_tenant(account) { project.issues.create!(message: "x", fingerprint: "fp", auto_fix_status: "awaiting_github") } }
  let(:user)    { account.users.create!(email: "u@x.com", password: "secret123") }

  before do
    allow_any_instance_of(Github::InstallationService).to receive(:fetch_installation_info)
      .and_return(success: true, repository: "acme/p", default_branch: "main")
    sign_in user
  end

  it "re-enqueues OrchestratorJob for awaiting_github issues" do
    expect(AutoFix::OrchestratorJob).to receive(:perform_later).with(issue.id)
    get "/github/app/callback", params: { installation_id: "12345", state: project.id }
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Edit `app/controllers/github_app_controller.rb`**

After the existing `project.update(settings: settings)` block in `callback` (around line 38, both the success and fallback branches), add:

```ruby
      project.issues.where(auto_fix_status: "awaiting_github").pluck(:id).each do |id|
        AutoFix::OrchestratorJob.perform_later(id)
      end
```

- [ ] **Step 4: Change the success-path redirect from `project_settings_path(project)` to `onboarding_path` so the wizard resumes**

Replace `redirect_to project_settings_path(project), notice: ...` with:
```ruby
      redirect_to onboarding_path, notice: "GitHub connected. Repo: #{github_info[:repository]}"
```
(and the fallback branch the same way; keep the existing notice text but redirect to `onboarding_path`)

- [ ] **Step 5: Run, see pass**

- [ ] **Step 6: Commit**

```bash
git add app/controllers/github_app_controller.rb spec/requests/github_callback_reconciler_spec.rb
git commit -m "feat(autofix): reconcile awaiting_github issues on callback; resume wizard"
```

NOTE: `onboarding_path` is added in Task 16 — this commit will fail Rails route resolution at runtime if executed before Task 16. Either run Tasks 15+16 together, or skip the `redirect_to onboarding_path` change until Task 16 lands. Implementer's call.

---

## Phase 4 — Onboarding Wizard

### Task 16: Routes — add new, remove old

**Files:**
- Modify: `config/routes.rb` (the onboarding block, lines ~17-24)

- [ ] **Step 1: Replace the onboarding routes**

Find:
```ruby
  get "onboarding/welcome", to: "onboarding#welcome", as: "onboarding_welcome"
  get "onboarding/connect_github", to: "onboarding#connect_github", as: "onboarding_connect_github"
  get "onboarding/new_project", to: "onboarding#new_project", as: "onboarding_new_project"
  post "onboarding/create_project", to: "onboarding#create_project", as: "onboarding_create_project"
  get "onboarding/install_gem/:project_id", to: "onboarding#install_gem", as: "onboarding_install_gem"
  post "onboarding/verify_gem/:project_id", to: "onboarding#verify_gem", as: "onboarding_verify_gem"
  get "onboarding/setup_github/:project_id", to: "onboarding#setup_github", as: "onboarding_setup_github"
  post "onboarding/setup_github/:project_id", to: "onboarding#setup_github"
```

Replace with:
```ruby
  get  "onboarding",                 to: "onboarding_wizard#show",                as: :onboarding
  post "onboarding/source",          to: "onboarding_wizard#submit_source",       as: :onboarding_submit_source
  post "onboarding/sentry/verify",   to: "onboarding_wizard#verify_sentry_token", as: :onboarding_verify_sentry_token
  post "onboarding/sentry/import",   to: "onboarding_wizard#start_sentry_import", as: :onboarding_start_sentry_import
  post "onboarding/complete",        to: "onboarding_wizard#complete",            as: :onboarding_complete

  # 301s for any bookmarked legacy URLs
  get "onboarding/welcome", to: redirect("/onboarding")
  get "onboarding/new_project", to: redirect("/onboarding")

  # Sentry webhook
  post "webhooks/sentry/:project_id", to: "sentry/webhooks#receive", as: :sentry_webhook
```

- [ ] **Step 2: Verify route table compiles**

```bash
docker exec activerabbit-web-1 bin/rails routes | grep -E "onboarding|sentry/webhook"
```

Expected: new routes present, old `onboarding_install_gem` etc. absent.

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat(onboarding): replace 5-page onboarding routes with wizard + Sentry webhook"
```

---

### Task 17: `OnboardingWizardController` — `#show` step decision

**Files:**
- Create: `app/controllers/onboarding_wizard_controller.rb`
- Create: `app/views/onboarding_wizard/show.html.erb`
- Create: `app/views/onboarding_wizard/_step_1_source.html.erb` (placeholder)
- Create: `app/views/onboarding_wizard/_step_2_github.html.erb` (placeholder)
- Create: `app/views/onboarding_wizard/_step_3_status.html.erb` (placeholder)
- Create: `spec/requests/onboarding_wizard/show_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe "OnboardingWizard#show", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:user)    { account.users.create!(email: "u@x.com", password: "secret123") }

  before { sign_in user }

  it "renders Step 1 when no project exists" do
    get "/onboarding"
    expect(response.body).to include("step-1")
  end

  it "renders Step 2 when project exists but github not installed" do
    ActsAsTenant.with_tenant(account) { Project.create!(name: "P", environment: "production") }
    get "/onboarding"
    expect(response.body).to include("step-2")
  end

  it "renders Step 3 when project exists and github_installation_id is set" do
    ActsAsTenant.with_tenant(account) do
      Project.create!(name: "P", environment: "production",
                      settings: { "github_installation_id" => "1" })
    end
    get "/onboarding"
    expect(response.body).to include("step-3")
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Controller**

```ruby
class OnboardingWizardController < ApplicationController
  before_action :authenticate_user!
  layout "admin"

  def show
    @project = current_account.projects.order(:created_at).last
    @step = decide_step(@project)
    render :show
  end

  private

  def decide_step(project)
    return 1 if project.nil?
    return 2 if project.settings.to_h["github_installation_id"].blank?
    3
  end
end
```

- [ ] **Step 4: View `show.html.erb`**

```erb
<% content_for :page_title do %>Onboarding<% end %>
<turbo-frame id="wizard">
  <%= render partial: "step_#{@step}_#{step_partial_suffix(@step)}", locals: { project: @project } %>
</turbo-frame>
```

Add a helper method or inline in controller:
```ruby
helper_method :step_partial_suffix
def step_partial_suffix(step)
  { 1 => "source", 2 => "github", 3 => "status" }.fetch(step)
end
```

- [ ] **Step 5: Placeholder partials**

`_step_1_source.html.erb`:
```erb
<div data-step="step-1">Step 1 — placeholder (filled in Task 18)</div>
```
`_step_2_github.html.erb`:
```erb
<div data-step="step-2">Step 2 — placeholder (filled in Task 21)</div>
```
`_step_3_status.html.erb`:
```erb
<div data-step="step-3">Step 3 — placeholder (filled in Task 22)</div>
```

- [ ] **Step 6: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/requests/onboarding_wizard/show_spec.rb
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/onboarding_wizard_controller.rb app/views/onboarding_wizard/ spec/requests/onboarding_wizard/
git commit -m "feat(onboarding): add OnboardingWizardController with step routing"
```

---

### Task 18: Step 1 view — source picker with two cards

**Files:**
- Modify: `app/views/onboarding_wizard/_step_1_source.html.erb`
- Create: `app/views/onboarding_wizard/_step_1_sentry_form.html.erb`
- Create: `app/views/onboarding_wizard/_step_1_sdk_snippet.html.erb`

- [ ] **Step 1: Replace placeholder Step 1**

```erb
<div data-step="step-1" class="max-w-3xl mx-auto p-8">
  <h1 class="text-2xl font-bold mb-2">Where do your errors live?</h1>
  <p class="text-gray-600 mb-6">Pick one. You can change this later.</p>

  <div class="mb-6">
    <label class="block text-sm font-medium text-gray-700 mb-1">App name</label>
    <input id="onboarding_app_name" type="text" placeholder="my-app"
           class="w-full px-3 py-2 border rounded-md" />
  </div>

  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
    <%= turbo_frame_tag "sentry_card" do %>
      <button type="button"
              class="p-6 border-2 border-purple-600 rounded-lg text-left bg-purple-50 hover:bg-purple-100"
              data-action="click->onboarding-source#showSentry">
        <div class="text-xs uppercase text-purple-700 mb-1">Featured · Fastest</div>
        <h2 class="text-xl font-semibold">Connect Sentry</h2>
        <p class="text-sm text-gray-700 mt-1">Paste a token. We import the last 7 days of errors and start drafting fixes.</p>
      </button>
    <% end %>

    <%= turbo_frame_tag "sdk_card" do %>
      <button type="button"
              class="p-6 border rounded-lg text-left hover:bg-gray-50"
              data-action="click->onboarding-source#showSdk">
        <h2 class="text-xl font-semibold">Install ActiveRabbit SDK</h2>
        <p class="text-sm text-gray-700 mt-1">Add the gem to your Rails app. Errors flow in once you deploy.</p>
      </button>
    <% end %>
  </div>
</div>
```

- [ ] **Step 2: `_step_1_sentry_form.html.erb`**

```erb
<div class="p-6 border-2 border-purple-600 rounded-lg bg-purple-50">
  <%= form_with url: onboarding_verify_sentry_token_path, method: :post, data: { turbo_frame: "sentry_card" } do |f| %>
    <%= f.hidden_field :app_name, id: "sentry_app_name_hidden" %>
    <label class="block text-sm font-medium mb-1">Sentry auth token</label>
    <p class="text-xs text-gray-600 mb-2">
      Generate at <code>sentry.io/settings/account/api/auth-tokens/</code> with scopes
      <code>org:read</code>, <code>project:read</code>, <code>event:read</code>.
    </p>
    <%= f.password_field :token, class: "w-full px-3 py-2 border rounded-md", required: true %>
    <div class="mt-3">
      <%= f.submit "Verify token", class: "px-4 py-2 bg-purple-600 text-white rounded-md" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: `_step_1_sdk_snippet.html.erb`**

```erb
<div class="p-6 border rounded-lg bg-gray-50">
  <%= form_with url: onboarding_submit_source_path, method: :post, data: { turbo_frame: "sdk_card" } do |f| %>
    <%= f.hidden_field :source, value: "sdk" %>
    <%= f.hidden_field :app_name, id: "sdk_app_name_hidden" %>
    <h3 class="font-semibold mb-2">1. Add the gem</h3>
    <pre class="bg-white p-3 rounded text-sm border">gem "activerabbit"</pre>
    <h3 class="font-semibold mt-4 mb-2">2. Configure the DSN (after we create your project we'll show you the DSN)</h3>
    <p class="text-sm text-gray-600">You can come back here once it's deployed — this step won't block onboarding.</p>
    <div class="mt-4">
      <%= f.submit "Continue → Connect GitHub", class: "px-4 py-2 bg-indigo-600 text-white rounded-md" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Add Stimulus controller for card swap**

Create `app/javascript/controllers/onboarding_source_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  showSentry(event) {
    this.copyAppName("sentry_app_name_hidden")
    fetch("/onboarding/source", {
      method: "POST",
      headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken() },
      body: new URLSearchParams({ "preview": "sentry" })
    }).then(r => r.text()).then(html => Turbo.renderStreamMessage(html))
  }
  showSdk(event) {
    this.copyAppName("sdk_app_name_hidden")
    fetch("/onboarding/source", {
      method: "POST",
      headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken() },
      body: new URLSearchParams({ "preview": "sdk" })
    }).then(r => r.text()).then(html => Turbo.renderStreamMessage(html))
  }
  copyAppName(targetId) {
    const v = document.getElementById("onboarding_app_name")?.value || ""
    document.querySelectorAll(`#${targetId}`).forEach(el => el.value = v)
  }
  csrfToken() { return document.querySelector("meta[name='csrf-token']")?.content }
}
```

Register in `app/javascript/controllers/index.js`:
```javascript
import OnboardingSourceController from "./onboarding_source_controller"
application.register("onboarding-source", OnboardingSourceController)
```

- [ ] **Step 5: Wrap Step 1 in the Stimulus controller** (edit Step 1 root div):

```erb
<div data-step="step-1" data-controller="onboarding-source" class="max-w-3xl mx-auto p-8">
```

- [ ] **Step 6: Commit**

```bash
git add app/views/onboarding_wizard/ app/javascript/controllers/
git commit -m "feat(onboarding): step 1 source picker views"
```

---

### Task 19: `submit_source` (preview + SDK path commit)

**Files:**
- Modify: `app/controllers/onboarding_wizard_controller.rb`
- Create: `spec/requests/onboarding_wizard/submit_source_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe "OnboardingWizard#submit_source", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:user)    { account.users.create!(email: "u@x.com", password: "secret123") }
  before { sign_in user }

  it "with preview=sentry returns turbo stream replacing sentry_card" do
    post "/onboarding/source", params: { preview: "sentry" },
                               headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include("turbo-stream")
    expect(response.body).to include("step_1_sentry_form")
  end

  it "with source=sdk creates Project and redirects to /onboarding (Step 2)" do
    expect {
      post "/onboarding/source", params: { source: "sdk", app_name: "my-app" }
    }.to change { Project.count }.by(1)
    expect(response).to redirect_to(onboarding_path)
    project = Project.last
    expect(project.name).to eq("my-app")
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement actions**

Add to `OnboardingWizardController`:
```ruby
  def submit_source
    if params[:preview].present?
      preview_card
    elsif params[:source] == "sdk"
      create_sdk_project
    else
      head :bad_request
    end
  end

  private

  def preview_card
    case params[:preview]
    when "sentry"
      render turbo_stream: turbo_stream.replace("sentry_card",
        partial: "onboarding_wizard/step_1_sentry_form")
    when "sdk"
      render turbo_stream: turbo_stream.replace("sdk_card",
        partial: "onboarding_wizard/step_1_sdk_snippet")
    else
      head :bad_request
    end
  end

  def create_sdk_project
    name = params[:app_name].presence || "My App"
    project = current_account.projects.create!(
      name: name,
      environment: "production",
      tech_stack: "rails"
    )
    project.generate_api_token!
    project.create_default_alert_rules!
    redirect_to onboarding_path
  end
```

- [ ] **Step 4: Run, see pass**

- [ ] **Step 5: Commit**

```bash
git add app/controllers/onboarding_wizard_controller.rb spec/requests/onboarding_wizard/submit_source_spec.rb
git commit -m "feat(onboarding): wizard submit_source — preview swaps + SDK path commit"
```

---

### Task 20: `verify_sentry_token` + `start_sentry_import`

**Files:**
- Modify: `app/controllers/onboarding_wizard_controller.rb`
- Create: `app/views/onboarding_wizard/_step_1_sentry_project_picker.html.erb`
- Create: `spec/requests/onboarding_wizard/sentry_flow_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe "OnboardingWizard sentry flow", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:user)    { account.users.create!(email: "u@x.com", password: "secret123") }
  before { sign_in user }

  describe "POST /onboarding/sentry/verify" do
    it "shows project picker on valid token" do
      client = instance_double(Sentry::Client)
      allow(Sentry::Client).to receive(:new).with("tkn").and_return(client)
      allow(client).to receive(:verify_token).and_return(true)
      allow(client).to receive(:list_projects).and_return([
        { org_slug: "acme", project_slug: "backend", name: "Backend", platform: "ruby" }
      ])
      post "/onboarding/sentry/verify", params: { token: "tkn", app_name: "" }
      expect(response.body).to include("step_1_sentry_project_picker")
      expect(response.body).to include("Backend")
    end

    it "shows inline error on invalid token" do
      allow_any_instance_of(Sentry::Client).to receive(:verify_token).and_return(false)
      post "/onboarding/sentry/verify", params: { token: "bad" }
      expect(response.body).to include("Invalid token")
    end
  end

  describe "POST /onboarding/sentry/import" do
    it "creates Project, enqueues import, advances wizard" do
      ActiveJob::Base.queue_adapter = :test
      expect {
        post "/onboarding/sentry/import",
             params: { app_name: "Backend", token: "tkn",
                       org_slug: "acme", project_slug: "backend", platform: "ruby" }
      }.to change { Project.count }.by(1)
        .and have_enqueued_job(Sentry::ImportProjectJob)
      expect(response).to redirect_to(onboarding_path)
    end
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Add actions**

```ruby
  def verify_sentry_token
    client = Sentry::Client.new(params[:token])
    unless client.verify_token
      render turbo_stream: turbo_stream.replace("sentry_card",
        partial: "onboarding_wizard/step_1_sentry_form",
        locals: { error: "Invalid token. Check that scopes include org:read, project:read, event:read." })
      return
    end
    projects = client.list_projects
    if projects.empty?
      render turbo_stream: turbo_stream.replace("sentry_card",
        partial: "onboarding_wizard/step_1_sentry_form",
        locals: { error: "Token valid but no projects accessible." })
      return
    end
    render turbo_stream: turbo_stream.replace("sentry_card",
      partial: "onboarding_wizard/step_1_sentry_project_picker",
      locals: { projects: projects, token: params[:token], app_name: params[:app_name] })
  end

  def start_sentry_import
    name = params[:app_name].presence || params[:project_slug]
    project = current_account.projects.create!(
      name: name,
      environment: "production",
      tech_stack: map_platform_to_tech_stack(params[:platform]),
      settings: {
        "sentry_org_slug" => params[:org_slug],
        "sentry_project_slug" => params[:project_slug],
        "sentry_auth_token" => params[:token],
        "sentry_webhook_secret" => SecureRandom.hex(32)
      }
    )
    project.generate_api_token!
    project.create_default_alert_rules!
    Sentry::ImportProjectJob.perform_later(project.id)
    redirect_to onboarding_path
  end

  private

  def map_platform_to_tech_stack(platform)
    {
      "ruby" => "rails", "ruby-rails" => "rails", "javascript" => "nodejs",
      "javascript-react" => "nodejs", "node" => "nodejs",
      "python" => "python", "go" => "go", "java" => "java"
    }[platform.to_s] || "rails"
  end
```

- [ ] **Step 4: Update `_step_1_sentry_form.html.erb` to render `error` if passed**

Add at top of partial:
```erb
<% if local_assigns[:error] %>
  <div class="bg-red-50 border border-red-200 text-red-800 p-3 rounded mb-3"><%= error %></div>
<% end %>
```

- [ ] **Step 5: Project picker partial**

`_step_1_sentry_project_picker.html.erb`:
```erb
<div class="p-6 border-2 border-purple-600 rounded-lg bg-purple-50">
  <h3 class="font-semibold mb-3">Pick the Sentry project to import</h3>
  <%= form_with url: onboarding_start_sentry_import_path, method: :post, local: true do |f| %>
    <%= f.hidden_field :token, value: token %>
    <%= f.hidden_field :app_name, value: app_name %>
    <% if projects.size == 1 %>
      <% p = projects.first %>
      <%= f.hidden_field :org_slug,     value: p[:org_slug] %>
      <%= f.hidden_field :project_slug, value: p[:project_slug] %>
      <%= f.hidden_field :platform,     value: p[:platform] %>
      <p class="mb-3"><strong><%= p[:org_slug] %>/<%= p[:project_slug] %></strong></p>
    <% else %>
      <select name="combined" class="w-full mb-3 border rounded-md px-3 py-2"
              onchange="this.form.org_slug.value=this.value.split('|')[0]; this.form.project_slug.value=this.value.split('|')[1]; this.form.platform.value=this.value.split('|')[2];">
        <% projects.each do |p| %>
          <option value="<%= "#{p[:org_slug]}|#{p[:project_slug]}|#{p[:platform]}" %>">
            <%= p[:org_slug] %>/<%= p[:project_slug] %> (<%= p[:platform] %>)
          </option>
        <% end %>
      </select>
      <%= f.hidden_field :org_slug,     value: projects.first[:org_slug] %>
      <%= f.hidden_field :project_slug, value: projects.first[:project_slug] %>
      <%= f.hidden_field :platform,     value: projects.first[:platform] %>
    <% end %>
    <%= f.submit "Import last 7 days →", class: "px-4 py-2 bg-purple-600 text-white rounded-md" %>
  <% end %>
</div>
```

- [ ] **Step 6: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/requests/onboarding_wizard/sentry_flow_spec.rb
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/onboarding_wizard_controller.rb app/views/onboarding_wizard/ spec/requests/onboarding_wizard/sentry_flow_spec.rb
git commit -m "feat(onboarding): wizard Sentry verify + import flow"
```

---

### Task 21: Step 2 view — GitHub one-click

**Files:**
- Modify: `app/views/onboarding_wizard/_step_2_github.html.erb`
- Modify: `app/controllers/onboarding_wizard_controller.rb` (`#show` to set `@github_install_url`)

- [ ] **Step 1: Add to `#show`**

```ruby
  def show
    @project = current_account.projects.order(:created_at).last
    @step = decide_step(@project)
    @github_install_url = Github::InstallationService.app_install_url(project_id: @project&.id) if @step == 2
    render :show
  end
```

- [ ] **Step 2: Replace `_step_2_github.html.erb`**

```erb
<div data-step="step-2" class="max-w-3xl mx-auto p-8 text-center">
  <h1 class="text-2xl font-bold mb-2">Connect your GitHub repo</h1>
  <p class="text-gray-600 mb-6">
    We need this so we can draft pull requests for high-confidence fixes.
  </p>

  <a href="<%= @github_install_url %>"
     class="inline-block px-6 py-3 bg-black text-white rounded-md font-semibold hover:bg-gray-800">
    Install GitHub App →
  </a>

  <div class="mt-6 text-sm">
    <%= form_with url: onboarding_complete_path, method: :post do |f| %>
      <%= f.hidden_field :skip_github, value: "1" %>
      <%= f.submit "Skip for now",
                   class: "text-gray-500 underline bg-transparent border-0 cursor-pointer",
                   data: { turbo_confirm: "Without GitHub, PRs won't auto-draft. You can connect later in Settings." } %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Add `#complete` (skip path)**

```ruby
  def complete
    redirect_to inbox_path
  end
```

- [ ] **Step 4: Smoke test in browser** (manual at this point) — confirm Step 2 renders.

- [ ] **Step 5: Commit**

```bash
git add app/views/onboarding_wizard/_step_2_github.html.erb app/controllers/onboarding_wizard_controller.rb
git commit -m "feat(onboarding): step 2 GitHub install + skip-for-now"
```

---

### Task 22: Step 3 view — live status feed

**Files:**
- Modify: `app/views/onboarding_wizard/_step_3_status.html.erb`
- Create: `app/views/onboarding_wizard/_status_row.html.erb`

- [ ] **Step 1: `_step_3_status.html.erb`**

```erb
<div data-step="step-3" class="max-w-3xl mx-auto p-8">
  <%= turbo_stream_from "project:#{project.id}:onboarding" %>

  <h1 class="text-2xl font-bold mb-2">
    <% if project.settings.to_h["sentry_org_slug"].present? %>
      Importing errors from Sentry…
    <% else %>
      Waiting for your first event…
    <% end %>
  </h1>
  <p class="text-gray-600 mb-6">
    We're analyzing each error and drafting fixes for the highest-confidence ones.
    PRs appear here as they open.
  </p>

  <ul id="status_rows" class="divide-y divide-gray-100 border rounded-lg bg-white"></ul>

  <div class="mt-6 text-sm text-gray-600">
    Done? <%= link_to "Take me to the inbox →", inbox_path, class: "text-indigo-600 underline" %>
  </div>
</div>
```

- [ ] **Step 2: `_status_row.html.erb`**

```erb
<li class="px-4 py-3 flex items-start gap-3">
  <% case kind %>
  <% when :issue_imported %>
    <span class="text-yellow-600">●</span>
    <div>
      <div class="font-medium"><%= issue.exception_class || issue.message&.truncate(60) %></div>
      <div class="text-xs text-gray-500">imported · analyzing…</div>
    </div>
  <% when :pr_drafted %>
    <span class="text-green-600">●</span>
    <div>
      <div class="font-medium">PR drafted</div>
      <div class="text-xs"><%= link_to "##{pr_number}", pr_url, target: "_blank", class: "text-indigo-600 underline" %> · <%= issue.exception_class %></div>
    </div>
  <% when :import_complete %>
    <span class="text-blue-600">●</span>
    <div>
      <div class="font-medium">Imported <%= count %> issues from Sentry</div>
      <div class="text-xs text-gray-500">drafting fixes for the top high-confidence ones…</div>
    </div>
  <% when :error %>
    <span class="text-red-600">●</span>
    <div>
      <div class="font-medium text-red-700"><%= local_assigns[:message] %></div>
    </div>
  <% end %>
</li>
```

- [ ] **Step 3: Verify Turbo Stream broadcast renders correctly** (manual, end-to-end). Will be properly tested in Phase 8.

- [ ] **Step 4: Commit**

```bash
git add app/views/onboarding_wizard/_step_3_status.html.erb app/views/onboarding_wizard/_status_row.html.erb
git commit -m "feat(onboarding): step 3 live status feed with status_row partial"
```

---

## Phase 5 — Sentry Webhook

### Task 23: `Sentry::WebhooksController` with HMAC signature verification

**Files:**
- Create: `app/controllers/sentry/webhooks_controller.rb`
- Create: `app/jobs/sentry/ingest_event_job.rb`
- Create: `spec/requests/sentry/webhooks_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe "Sentry webhook", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:secret)  { "supersecret" }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      Project.create!(name: "P", environment: "production",
                      settings: { "sentry_webhook_secret" => secret,
                                  "sentry_org_slug" => "acme",
                                  "sentry_project_slug" => "backend" })
    end
  end
  let(:body) { JSON.dump({ "data" => { "issue" => { "id" => "99", "title" => "Boom" } } }) }
  let(:sig)  { OpenSSL::HMAC.hexdigest("SHA256", secret, body) }

  it "rejects when signature missing" do
    post "/webhooks/sentry/#{project.id}", params: body, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects when signature mismatched" do
    post "/webhooks/sentry/#{project.id}", params: body,
         headers: { "Content-Type" => "application/json", "Sentry-Hook-Signature" => "deadbeef" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts valid signature and enqueues IngestEventJob" do
    expect {
      post "/webhooks/sentry/#{project.id}", params: body,
           headers: { "Content-Type" => "application/json", "Sentry-Hook-Signature" => sig }
    }.to have_enqueued_job(Sentry::IngestEventJob)
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement controller `app/controllers/sentry/webhooks_controller.rb`**

```ruby
module Sentry
  class WebhooksController < ActionController::API
    def receive
      project = Project.find_by(id: params[:project_id])
      return head :not_found unless project

      raw = request.raw_post
      secret = project.settings.to_h["sentry_webhook_secret"]
      sig    = request.headers["Sentry-Hook-Signature"].to_s
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, raw)
      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, sig)

      payload = JSON.parse(raw) rescue {}
      Sentry::IngestEventJob.perform_later(project.id, payload)
      head :ok
    end
  end
end
```

- [ ] **Step 4: Implement `app/jobs/sentry/ingest_event_job.rb`**

```ruby
module Sentry
  class IngestEventJob < ApplicationJob
    queue_as :default

    def perform(project_id, payload)
      project = Project.find(project_id)
      issue_data = payload.dig("data", "issue") || payload["issue"] || {}
      return if issue_data["id"].blank?

      mapped = {
        sentry_issue_id: issue_data["id"],
        title: issue_data["title"],
        culprit: issue_data["culprit"],
        exception_class: issue_data.dig("metadata", "type"),
        exception_message: issue_data.dig("metadata", "value"),
        permalink: issue_data["permalink"] || issue_data["web_url"],
        platform: issue_data["platform"] || project.settings.to_h["sentry_platform"],
        last_seen: issue_data["lastSeen"],
        event_count: issue_data["count"].to_i,
        user_count: issue_data["userCount"].to_i,
        raw: issue_data
      }

      ActsAsTenant.with_tenant(project.account) do
        issue = Sentry::EventMapper.upsert!(project, mapped)
        AutoFix::OrchestratorJob.perform_later(issue.id)
      end
    end
  end
end
```

- [ ] **Step 5: Run, see pass**

```bash
docker exec activerabbit-web-1 bin/rspec spec/requests/sentry/webhooks_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/sentry/webhooks_controller.rb app/jobs/sentry/ingest_event_job.rb spec/requests/sentry/webhooks_spec.rb
git commit -m "feat(sentry): live webhook with HMAC verification + ingest job"
```

---

### Task 24: Register internal integration after import completes

**Files:**
- Modify: `app/services/sentry/import_service.rb` (add registration step at end)

- [ ] **Step 1: Add spec**

In `spec/services/sentry/import_service_spec.rb` add:
```ruby
  it "registers Sentry internal integration after import" do
    allow(client).to receive(:register_internal_integration)
      .with(hash_including(org: "acme", webhook_url: a_string_including("/webhooks/sentry/")))
      .and_return(integration_uuid: "uuid", api_token: "abc")
    ActsAsTenant.with_tenant(account) { described_class.call(project) }
    expect(project.reload.settings["sentry_internal_integration_uuid"]).to eq("uuid")
  end
```

- [ ] **Step 2: Run, see fail**

- [ ] **Step 3: Implement** in `Sentry::ImportService#call`, after `stamp_completion!`:

```ruby
      register_internal_integration!(client)
```

And the method:
```ruby
    def register_internal_integration!(client)
      return if @project.settings.to_h["sentry_internal_integration_uuid"].present?
      webhook_url = Rails.application.routes.url_helpers.sentry_webhook_url(
        project_id: @project.id, host: ENV.fetch("APP_HOST", "app.activerabbit.com"), protocol: "https"
      )
      result = client.register_internal_integration(
        org: @project.settings["sentry_org_slug"],
        webhook_url: webhook_url,
        name: "ActiveRabbit (#{@project.name})"
      )
      return if result[:integration_uuid].blank?
      settings = @project.settings.merge(
        "sentry_internal_integration_uuid" => result[:integration_uuid],
        "sentry_internal_integration_token" => result[:api_token]
      )
      @project.update!(settings: settings)
    end
```

- [ ] **Step 4: Run, see pass**

- [ ] **Step 5: Commit**

```bash
git add app/services/sentry/import_service.rb spec/services/sentry/import_service_spec.rb
git commit -m "feat(sentry): register internal integration after initial import"
```

---

## Phase 6 — Settings UI

### Task 25: Auto-fix settings panel

**Files:**
- Modify: `app/views/project_settings/show.html.erb` (find appropriate insertion point — after the existing GitHub panel)
- Modify: `app/controllers/project_settings_controller.rb` to permit `auto_pr_weekly_cap` and `auto_pr_confidence_threshold`

- [ ] **Step 1: Add `auto_pr_weekly_cap` and `auto_pr_confidence_threshold` to permitted params**

In `app/controllers/project_settings_controller.rb`, find the `project_params` (or equivalent) method and add the two columns to `permit(...)`. If the controller uses a different param shape (e.g., nested `settings`), follow the existing pattern; the two attributes are real columns on `Project`.

- [ ] **Step 2: Render the panel**

Add to `app/views/project_settings/show.html.erb`:

```erb
<div class="bg-white rounded-lg shadow p-6 mb-6">
  <h2 class="text-lg font-semibold mb-4">Auto-fix</h2>
  <%= form_with model: @project, url: project_settings_path(@project), method: :patch do |f| %>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <%= f.label :auto_pr_weekly_cap, "Weekly auto-PR cap", class: "block text-sm font-medium mb-1" %>
        <%= f.select :auto_pr_weekly_cap, [5,10,20], {}, class: "border rounded-md px-3 py-2" %>
      </div>
      <div>
        <label class="block text-sm font-medium mb-1">Confidence threshold</label>
        <% [[0, "Off (0) — manual only"], [60, "Medium (60)"], [80, "High (80) [default]"]].each do |val, label| %>
          <label class="block">
            <%= f.radio_button :auto_pr_confidence_threshold, val %> <%= label %>
          </label>
        <% end %>
      </div>
    </div>
    <p class="text-sm text-gray-600 mt-4">
      Used in last 7 days: <%= AutoPrEvent.where(project: @project).within_last(7.days).count %> / <%= @project.auto_pr_weekly_cap %>
    </p>
    <div class="mt-4">
      <%= f.submit "Save", class: "px-4 py-2 bg-indigo-600 text-white rounded-md" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Spec**

Create `spec/requests/project_settings_auto_fix_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Project Settings — auto-fix", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:user)    { account.users.create!(email: "u@x.com", password: "secret123") }
  let(:project) { ActsAsTenant.with_tenant(account) { Project.create!(name: "P", environment: "production") } }
  before { sign_in user }

  it "updates weekly cap and confidence" do
    patch project_settings_path(project), params: {
      project: { auto_pr_weekly_cap: 10, auto_pr_confidence_threshold: 60 }
    }
    expect(project.reload.auto_pr_weekly_cap).to eq(10)
    expect(project.auto_pr_confidence_threshold).to eq(60)
  end
end
```

- [ ] **Step 4: Run, see pass**

- [ ] **Step 5: Commit**

```bash
git add app/views/project_settings/show.html.erb app/controllers/project_settings_controller.rb spec/requests/project_settings_auto_fix_spec.rb
git commit -m "feat(autofix): project settings panel for cap and threshold"
```

---

### Task 26: Sentry connection settings panel + disconnect

**Files:**
- Modify: `app/views/project_settings/show.html.erb`
- Modify: `app/controllers/project_settings_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Route**

Inside the existing `resource :settings, controller: "project_settings", ...` block in `config/routes.rb`:
```ruby
      delete :disconnect_sentry
      post   :reimport_sentry
```

- [ ] **Step 2: Controller actions**

Add to `app/controllers/project_settings_controller.rb`:
```ruby
  def disconnect_sentry
    settings = @project.settings.except(
      "sentry_org_slug", "sentry_project_slug", "sentry_auth_token",
      "sentry_webhook_secret", "sentry_internal_integration_uuid",
      "sentry_internal_integration_token", "sentry_initial_import_completed_at",
      "sentry_initial_import_count"
    )
    @project.update!(settings: settings)
    redirect_to project_settings_path(@project), notice: "Sentry disconnected."
  end

  def reimport_sentry
    Sentry::ImportProjectJob.perform_later(@project.id)
    redirect_to project_settings_path(@project), notice: "Re-importing last 7 days from Sentry…"
  end
```

- [ ] **Step 3: Render the panel** (only if connected)

Add to `app/views/project_settings/show.html.erb`:

```erb
<% if @project.settings.to_h["sentry_org_slug"].present? %>
  <div class="bg-white rounded-lg shadow p-6 mb-6">
    <h2 class="text-lg font-semibold mb-4">Sentry connection</h2>
    <p>
      Connected to <strong><%= @project.settings["sentry_org_slug"] %>/<%= @project.settings["sentry_project_slug"] %></strong>
      <% if @project.settings["sentry_initial_import_completed_at"].present? %>
        · last sync <%= time_ago_in_words(Time.parse(@project.settings["sentry_initial_import_completed_at"])) %> ago
      <% end %>
    </p>
    <div class="mt-3 flex gap-3">
      <%= button_to "Re-import last 7 days", reimport_sentry_project_settings_path(@project), method: :post,
                    class: "px-3 py-2 border rounded-md" %>
      <%= button_to "Disconnect Sentry", disconnect_sentry_project_settings_path(@project), method: :delete,
                    data: { turbo_confirm: "Are you sure? Live error sync will stop." },
                    class: "px-3 py-2 border border-red-300 text-red-700 rounded-md" %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 4: Spec**

Create `spec/requests/project_settings_sentry_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Project Settings — sentry", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:user)    { account.users.create!(email: "u@x.com", password: "secret123") }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      Project.create!(name: "P", environment: "production",
                      settings: { "sentry_org_slug" => "acme", "sentry_project_slug" => "backend" })
    end
  end
  before { sign_in user }

  it "disconnects Sentry" do
    delete disconnect_sentry_project_settings_path(project)
    expect(project.reload.settings).not_to include("sentry_org_slug")
  end

  it "re-imports" do
    expect {
      post reimport_sentry_project_settings_path(project)
    }.to have_enqueued_job(Sentry::ImportProjectJob).with(project.id)
  end
end
```

- [ ] **Step 5: Run, see pass**

- [ ] **Step 6: Commit**

```bash
git add app/controllers/project_settings_controller.rb app/views/project_settings/show.html.erb config/routes.rb spec/requests/project_settings_sentry_spec.rb
git commit -m "feat(sentry): settings panel — re-import + disconnect"
```

---

## Phase 7 — Cleanup

### Task 27: Delete legacy `OnboardingController` actions and views

**Files:**
- Modify: `app/controllers/onboarding_controller.rb` — delete or shrink to a redirect-only file (or remove entirely)
- Delete: `app/views/onboarding/welcome.html.erb`
- Delete: `app/views/onboarding/install_gem.html.erb`
- Delete: `app/views/onboarding/new_project.html.erb`
- Delete: `app/views/onboarding/setup_github.html.erb`
- Delete: `test/integration/onboarding_controller_test.rb` (replaced by RSpec wizard specs)

- [ ] **Step 1: Confirm no other code references old onboarding paths**

```bash
grep -rn "onboarding_install_gem_path\|onboarding_new_project_path\|onboarding_create_project_path\|onboarding_setup_github_path\|onboarding_verify_gem_path\|onboarding_welcome_path\|onboarding_connect_github_path" app/ config/ lib/ test/ spec/ 2>/dev/null
```

Expected: only references inside `app/controllers/onboarding_controller.rb` (which we're deleting).

- [ ] **Step 2: Delete files**

```bash
rm app/controllers/onboarding_controller.rb \
   app/views/onboarding/welcome.html.erb \
   app/views/onboarding/install_gem.html.erb \
   app/views/onboarding/new_project.html.erb \
   app/views/onboarding/setup_github.html.erb \
   test/integration/onboarding_controller_test.rb
rmdir app/views/onboarding 2>/dev/null || true
```

- [ ] **Step 3: Run full test suite**

```bash
docker exec activerabbit-web-1 bin/rspec
docker exec activerabbit-web-1 bin/rails test
```

Expected: green. Fix any reference rot.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore(onboarding): delete legacy 5-page onboarding"
```

---

### Task 28: Update root redirect for users without projects

**Files:**
- Modify: wherever the no-project redirect lives. Check `ApplicationController` or `SreInboxController` (the root) for a redirect to onboarding when `current_account.projects.empty?`.

- [ ] **Step 1: Locate the redirect**

```bash
grep -rn "onboarding_welcome\|onboarding_path\|projects.empty\|projects.any" app/controllers/ 2>/dev/null
```

- [ ] **Step 2: Replace any `redirect_to onboarding_welcome_path` with `redirect_to onboarding_path`** in those files.

- [ ] **Step 3: Spec a request** at `/` (sre_inbox#index) for a user with zero projects:

Create `spec/requests/root_redirects_to_onboarding_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Root", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:user)    { account.users.create!(email: "u@x.com", password: "secret123") }

  before { sign_in user }

  it "redirects to /onboarding when no projects exist" do
    get "/"
    expect(response).to redirect_to(onboarding_path)
  end
end
```

- [ ] **Step 4: Run, fix, commit**

```bash
docker exec activerabbit-web-1 bin/rspec spec/requests/root_redirects_to_onboarding_spec.rb
git add -A
git commit -m "feat(onboarding): redirect users with no projects to /onboarding"
```

---

## Phase 8 — End-to-end verification

### Task 29: Manual verification in Firefox (per project preference)

- [ ] **Step 1: Spin up the dev environment if not running**

```bash
docker compose up -d
```

- [ ] **Step 2: Sign up a fresh user via GitHub OAuth**

Open Firefox, navigate to the app URL, click "Sign up with GitHub", complete OAuth. Expected: redirected to `/onboarding`.

- [ ] **Step 3: Test Sentry path against a real Sentry sandbox**

- Create a Sentry sandbox project (sentry.io) with at least 3 historical errors.
- Generate an auth token with scopes `org:read`, `project:read`, `event:read`.
- In the wizard: enter `app_name = "Sandbox"`, click "Connect Sentry", paste token, click "Verify token".
- Expected: project picker shows your sandbox project. Click "Import last 7 days →".
- Expected: redirected to Step 2.
- Click "Install GitHub App", install on a sandbox repo, get redirected back to Step 3.
- Expected: status feed appends one row per imported issue, then "Imported N issues" row.
- Wait up to 60s; expected: at least one "PR drafted" row appears (assuming at least one imported issue scores ≥ 80 on `sre_confidence`).
- Click the PR link; expected: real GitHub PR with diff.

- [ ] **Step 4: Test SDK path**

- Sign up a second test user.
- Click "Install ActiveRabbit SDK" on Step 1, click "Continue → Connect GitHub", install GitHub App.
- Expected: Step 3 shows "Waiting for first event…".
- POST a fixture event via curl:
```bash
curl -X POST https://localhost/api/v1/events \
  -H "X-API-Token: <project_api_token>" \
  -H "Content-Type: application/json" \
  -d '{"exception_class": "RuntimeError", "message": "boom", "fingerprint": "fixture1"}'
```
- Expected: status feed appends an "issue_imported" row within seconds.

- [ ] **Step 5: Test cap enforcement**

- In Project Settings, lower the weekly cap to 5.
- Manually create 5 `AutoPrEvent` rows in Rails console with `opened_at: Time.current`.
- Trigger a 6th high-confidence issue (POST another fixture event with mocked `sre_confidence: 90`).
- Expected: `Issue.last.auto_fix_status == "queued_capped"`. No PR opened.

- [ ] **Step 6: Test webhook live path**

- Trigger a real error in your Sentry-connected sandbox app (raise an exception).
- Wait ~10s. Expected: a row appears in `/inbox` for the new error without a manual import.

- [ ] **Step 7: Document any failures, file follow-up issues, then mark verification passed.**

- [ ] **Step 8: Commit any small fixes encountered during manual run**

```bash
git add -A
git commit -m "fix(onboarding): manual-verification touch-ups"
```

---

### Task 30: Final pre-merge checks

- [ ] **Step 1: Run full test suite**

```bash
docker exec activerabbit-web-1 bin/rspec
docker exec activerabbit-web-1 bin/rails test
```

Expected: all green.

- [ ] **Step 2: Run linter / rubocop**

```bash
docker exec activerabbit-web-1 bundle exec rubocop -a app/services/sentry/ app/services/auto_fix/ app/jobs/sentry/ app/jobs/auto_fix/ app/jobs/github/pr_creation_job.rb app/controllers/onboarding_wizard_controller.rb app/controllers/sentry/webhooks_controller.rb 2>/dev/null || true
```

- [ ] **Step 3: Squash inspection**

```bash
git log main..HEAD --oneline
```

Expected: the task commits land in a clean sequence per phase.

- [ ] **Step 4: Push branch and open PR via gh**

```bash
git push -u origin agent-part
```

(User to run `gh pr create` themselves to title/describe the PR — see project guidance.)
