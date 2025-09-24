require 'rails_helper'

RSpec.describe Issue, type: :model do
  let(:project) { create(:project) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:fingerprint) }
    it { is_expected.to validate_presence_of(:exception_class) }
    it { is_expected.to validate_presence_of(:top_frame) }
    it { is_expected.to validate_presence_of(:controller_action) }
  end

  describe '.find_or_create_by_fingerprint' do
    it 'creates a new issue and increments counts properly' do
      issue = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'RuntimeError',
        top_frame: "/app/controllers/home_controller.rb:10:in `index'",
        controller_action: 'HomeController#index',
        sample_message: 'boom'
      )
      expect(issue).to be_persisted
      expect(issue.count).to eq(1)

      same = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'RuntimeError',
        top_frame: "/app/controllers/home_controller.rb:32:in `index'",
        controller_action: 'HomeController#index',
        sample_message: 'boom again'
      )
      expect(same.id).to eq(issue.id)
      expect(same.count).to eq(2)
    end
  end

  describe '#status transitions' do
    it 'sets wip/close/reopen' do
      issue = create(:issue, project: project)
      issue.mark_wip!
      expect(issue.status).to eq('wip')
      issue.close!
      expect(issue.status).to eq('closed')
      issue.reopen!
      expect(issue.status).to eq('open')
    end
  end
end
