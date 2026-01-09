require 'rails_helper'

RSpec.describe PerformanceIncident, type: :model do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:target) }
    it { is_expected.to validate_presence_of(:trigger_p95_ms) }
    it { is_expected.to validate_presence_of(:threshold_ms) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[open closed]) }
    it { is_expected.to validate_inclusion_of(:severity).in_array(%w[warning critical]) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
  end

  describe 'scopes' do
    let!(:open_incident) { create(:performance_incident, project: project, status: 'open') }
    let!(:closed_incident) { create(:performance_incident, project: project, status: 'closed', closed_at: Time.current) }
    let!(:warning_incident) { create(:performance_incident, project: project, severity: 'warning') }
    let!(:critical_incident) { create(:performance_incident, project: project, severity: 'critical') }

    it 'returns open incidents' do
      expect(described_class.open).to include(open_incident)
      expect(described_class.open).not_to include(closed_incident)
    end

    it 'returns closed incidents' do
      expect(described_class.closed).to include(closed_incident)
      expect(described_class.closed).not_to include(open_incident)
    end

    it 'filters by severity' do
      expect(described_class.warning).to include(warning_incident)
      expect(described_class.critical).to include(critical_incident)
    end
  end

  describe '.find_open_incident' do
    let!(:open_incident) { create(:performance_incident, project: project, target: 'UsersController#index', status: 'open') }
    let!(:closed_incident) { create(:performance_incident, project: project, target: 'UsersController#index', status: 'closed', closed_at: Time.current) }

    it 'finds open incident for target' do
      result = described_class.find_open_incident(project: project, target: 'UsersController#index')
      expect(result).to eq(open_incident)
    end

    it 'returns nil when no open incident exists' do
      open_incident.update!(status: 'closed', closed_at: Time.current)
      result = described_class.find_open_incident(project: project, target: 'UsersController#index')
      expect(result).to be_nil
    end
  end

  describe '.get_thresholds' do
    it 'returns default thresholds' do
      thresholds = described_class.get_thresholds(project, 'UsersController#index')

      expect(thresholds[:warning]).to eq(PerformanceIncident::DEFAULT_WARNING_THRESHOLD_MS)
      expect(thresholds[:critical]).to eq(PerformanceIncident::DEFAULT_CRITICAL_THRESHOLD_MS)
      expect(thresholds[:warmup_count]).to eq(PerformanceIncident::DEFAULT_WARMUP_COUNT)
      expect(thresholds[:cooldown_minutes]).to eq(PerformanceIncident::DEFAULT_COOLDOWN_MINUTES)
    end

    it 'respects project-level overrides' do
      project.update!(settings: {
        'performance_thresholds' => {
          'warning_ms' => 500,
          'critical_ms' => 1000
        }
      })

      thresholds = described_class.get_thresholds(project, 'UsersController#index')

      expect(thresholds[:warning]).to eq(500.0)
      expect(thresholds[:critical]).to eq(1000.0)
    end

    it 'respects per-endpoint overrides' do
      project.update!(settings: {
        'performance_thresholds' => {
          'warning_ms' => 500,
          'endpoints' => {
            'ReportsController#generate' => {
              'warning_ms' => 2000,
              'critical_ms' => 5000
            }
          }
        }
      })

      # Default endpoint uses project settings
      default_thresholds = described_class.get_thresholds(project, 'UsersController#index')
      expect(default_thresholds[:warning]).to eq(500.0)

      # Override endpoint uses specific settings
      override_thresholds = described_class.get_thresholds(project, 'ReportsController#generate')
      expect(override_thresholds[:warning]).to eq(2000.0)
      expect(override_thresholds[:critical]).to eq(5000.0)
    end
  end

  describe '.evaluate_endpoint' do
    let(:redis) { Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1") }

    before do
      # Clear Redis keys
      redis.del("perf_incident_warmup:#{project.id}:UsersController#index")
      redis.del("perf_incident_recovery:#{project.id}:UsersController#index")
    end

    context 'when p95 is below warning threshold' do
      it 'does not create an incident' do
        expect {
          described_class.evaluate_endpoint(
            project: project,
            target: 'UsersController#index',
            current_p95_ms: 500.0 # Below 750ms warning
          )
        }.not_to change { PerformanceIncident.count }
      end
    end

    context 'when p95 exceeds warning threshold' do
      it 'increments warm-up counter' do
        described_class.evaluate_endpoint(
          project: project,
          target: 'UsersController#index',
          current_p95_ms: 800.0 # Above 750ms warning
        )

        warmup_count = redis.get("perf_incident_warmup:#{project.id}:UsersController#index").to_i
        expect(warmup_count).to eq(1)
      end

      it 'creates incident after warm-up period' do
        # Simulate 3 consecutive breaches (default warmup_count)
        3.times do
          described_class.evaluate_endpoint(
            project: project,
            target: 'UsersController#index',
            current_p95_ms: 800.0
          )
        end

        expect(PerformanceIncident.count).to eq(1)
        incident = PerformanceIncident.last
        expect(incident.status).to eq('open')
        expect(incident.severity).to eq('warning')
        expect(incident.trigger_p95_ms).to eq(800.0)
      end
    end

    context 'when p95 exceeds critical threshold' do
      it 'creates critical incident after warm-up' do
        3.times do
          described_class.evaluate_endpoint(
            project: project,
            target: 'UsersController#index',
            current_p95_ms: 1600.0 # Above 1500ms critical
          )
        end

        incident = PerformanceIncident.last
        expect(incident.severity).to eq('critical')
      end
    end

    context 'when recovering from an incident' do
      let!(:open_incident) do
        create(:performance_incident,
          project: project,
          target: 'UsersController#index',
          status: 'open',
          trigger_p95_ms: 900.0,
          peak_p95_ms: 1000.0,
          threshold_ms: 750.0
        )
      end

      it 'closes incident after recovery period' do
        # Simulate 3 consecutive recoveries
        3.times do
          described_class.evaluate_endpoint(
            project: project,
            target: 'UsersController#index',
            current_p95_ms: 400.0 # Below threshold
          )
        end

        open_incident.reload
        expect(open_incident.status).to eq('closed')
        expect(open_incident.resolve_p95_ms).to eq(400.0)
      end
    end

    context 'cooldown period' do
      it 'does not reopen incident during cooldown' do
        # Create and close an incident
        incident = create(:performance_incident,
          project: project,
          target: 'UsersController#index',
          status: 'closed',
          closed_at: 5.minutes.ago # Within 10-minute cooldown
        )

        # Try to trigger a new incident
        3.times do
          described_class.evaluate_endpoint(
            project: project,
            target: 'UsersController#index',
            current_p95_ms: 900.0
          )
        end

        # Should not create a new incident due to cooldown
        expect(PerformanceIncident.open.count).to eq(0)
      end
    end
  end

  describe '#duration_minutes' do
    it 'calculates duration for closed incidents' do
      incident = create(:performance_incident,
        project: project,
        opened_at: 30.minutes.ago,
        closed_at: Time.current,
        status: 'closed'
      )

      expect(incident.duration_minutes).to eq(30)
    end

    it 'returns nil for open incidents' do
      incident = create(:performance_incident, project: project, status: 'open')
      expect(incident.duration_minutes).to be_nil
    end
  end

  describe '#status_emoji' do
    it 'returns correct emoji for critical open incident' do
      incident = build(:performance_incident, status: 'open', severity: 'critical')
      expect(incident.status_emoji).to eq('🔴')
    end

    it 'returns correct emoji for warning open incident' do
      incident = build(:performance_incident, status: 'open', severity: 'warning')
      expect(incident.status_emoji).to eq('🟡')
    end

    it 'returns correct emoji for closed incident' do
      incident = build(:performance_incident, status: 'closed')
      expect(incident.status_emoji).to eq('✅')
    end
  end
end

