require 'rails_helper'

RSpec.describe Github::BranchNameGenerator, type: :service do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:issue) do
    create(:issue,
      project: project,
      account: account,
      exception_class: "NoMethodError",
      sample_message: "undefined method `foo' for nil:NilClass",
      controller_action: "UsersController#show"
    )
  end

  let!(:ai_config) { create(:ai_provider_config, account: account, active: true) }
  let(:service) { described_class.new(account: account) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#initialize' do
    it 'accepts account' do
      service = described_class.new(account: account)
      expect(service).to be_a(Github::BranchNameGenerator)
    end
  end

  describe '#generate' do
    context 'with custom branch name' do
      it 'sanitizes and returns custom name' do
        result = service.generate(issue, "my fix branch")
        expect(result).to eq("ai-fix/my-fix-branch")
      end

      it 'preserves ai-fix/ prefix' do
        result = service.generate(issue, "ai-fix/my-branch")
        expect(result).to eq("ai-fix/my-branch")
      end
    end

    context 'with AI generation' do
      before do
        mock_message = double(content: "ai-fix/nomethoderror-users-show")
        mock_chat = double
        allow(mock_chat).to receive(:ask).and_return(mock_message)
        allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)
      end

      it 'generates branch name via AI' do
        result = service.generate(issue)

        expect(result).to be_present
        expect(result).to match(/^ai-fix\//)
      end
    end

    context 'without AI (no config)' do
      before do
        ai_config.update!(active: false)
      end

      it 'generates fallback branch name' do
        result = service.generate(issue)

        expect(result).to be_present
        expect(result).to start_with("ai-fix/")
        expect(result).to include("no-method")
      end
    end

    context 'when AI fails' do
      before do
        mock_chat = double
        allow(mock_chat).to receive(:ask).and_raise(RuntimeError, "API error")
        allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)
      end

      it 'falls back to generated name' do
        result = service.generate(issue)

        expect(result).to be_present
        expect(result).to include("fix")
      end
    end
  end

  describe 'branch name format' do
    before do
      mock_message = double(content: "ai-fix/nomethoderror-users-show")
      mock_chat = double
      allow(mock_chat).to receive(:ask).and_return(mock_message)
      allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)
    end

    it 'produces valid git branch name' do
      result = service.generate(issue)

      expect(result).to match(/^[a-z0-9\-\/]+$/)
      expect(result.length).to be <= 100
    end

    it 'starts with ai-fix/ prefix' do
      result = service.generate(issue)
      expect(result).to start_with("ai-fix/")
    end
  end
end
