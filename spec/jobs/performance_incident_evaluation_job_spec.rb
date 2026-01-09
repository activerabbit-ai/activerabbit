require 'rails_helper'

RSpec.describe PerformanceIncidentEvaluationJob, type: :job do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account, active: true) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#perform' do
    context 'with recent rollup data' do
      before do
        # Create rollup data for the last minute
        create(:perf_rollup,
          project: project,
          target: 'UsersController#index',
          timeframe: 'minute',
          timestamp: 1.minute.ago,
          p95_duration_ms: 900.0 # Above warning threshold
        )
      end

      it 'evaluates performance metrics for each project' do
        allow(PerformanceIncident).to receive(:evaluate_endpoint)

        described_class.new.perform

        expect(PerformanceIncident).to have_received(:evaluate_endpoint).with(
          hash_including(
            project: project,
            target: 'UsersController#index',
            environment: project.environment
          )
        )
      end
    end

    context 'without recent rollup data' do
      it 'does not create incidents' do
        expect {
          described_class.new.perform
        }.not_to change { PerformanceIncident.count }
      end
    end

    context 'with open incidents and no recent data' do
      let!(:stale_incident) do
        create(:performance_incident,
          project: project,
          target: 'OldController#action',
          status: 'open'
        )
      end

      it 'handles stale incidents (no recent data)' do
        allow(PerformanceIncident).to receive(:handle_recovery)

        described_class.new.perform

        expect(PerformanceIncident).to have_received(:handle_recovery).with(
          hash_including(
            project: project,
            target: 'OldController#action',
            open_incident: stale_incident
          )
        )
      end
    end

    context 'with multiple projects' do
      let(:project2) { create(:project, account: account, active: true) }

      before do
        create(:perf_rollup,
          project: project,
          target: 'UsersController#index',
          timeframe: 'minute',
          timestamp: 1.minute.ago,
          p95_duration_ms: 500.0
        )
        create(:perf_rollup,
          project: project2,
          target: 'OrdersController#create',
          timeframe: 'minute',
          timestamp: 1.minute.ago,
          p95_duration_ms: 600.0
        )
      end

      it 'evaluates all active projects' do
        allow(PerformanceIncident).to receive(:evaluate_endpoint)

        described_class.new.perform

        expect(PerformanceIncident).to have_received(:evaluate_endpoint).twice
      end
    end

    context 'with inactive projects' do
      before do
        project.update!(active: false)
      end

      it 'skips inactive projects' do
        allow(PerformanceIncident).to receive(:evaluate_endpoint)

        described_class.new.perform

        expect(PerformanceIncident).not_to have_received(:evaluate_endpoint)
      end
    end
  end
end
