require 'rails_helper'

RSpec.describe 'Performance PR', type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user, account: user.account) }

  before do
    sign_in user
  end

  it 'redirects to GitHub on success' do
    allow_any_instance_of(GithubPrService).to receive(:create_pr_for_performance_target)
      .and_return({ success: true, pr_url: 'https://github.com/owner/repo/pull/1' })

    post project_performance_action_create_pr_path(project, target: 'HomeController#index')
    expect(response).to have_http_status(:found)
    expect(response.redirect_url).to match(%r{https://github.com/owner/repo/pull/1})
  end

  it 'shows alert on failure' do
    allow_any_instance_of(GithubPrService).to receive(:create_pr_for_performance_target)
      .and_return({ success: false, error: 'Repo not found' })

    post project_performance_action_create_pr_path(project, target: 'HomeController#index')
    follow_redirect!
    expect(response.body).to match(/Repo not found/)
  end
end


