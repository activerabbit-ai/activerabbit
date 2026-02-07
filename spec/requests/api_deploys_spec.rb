require 'rails_helper'

RSpec.describe 'API::V1::Deploys', type: :request, api: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project, user: user, account: account)
    end
  end
  let(:token) do
    ActsAsTenant.with_tenant(account) do
      create(:api_token, project: project, account: account)
    end
  end
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Project-Token' => token.token } }

  describe 'POST /api/v1/deploys' do
    it 'creates a deploy and associated release' do
      body = {
        project_slug: project.slug,
        version: 'v1.0.0',
        environment: 'production',
        status: 'success',
        user: user.email,
        started_at: 1.minute.ago.iso8601,
        finished_at: Time.current.iso8601
      }.to_json

      expect {
        post '/api/v1/deploys', params: body, headers: headers
      }.to change { ActsAsTenant.with_tenant(account) { Deploy.count } }.by(1)
        .and change { ActsAsTenant.with_tenant(account) { Release.count } }.by(1)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['ok']).to eq(true)
      expect(json['deploy_id']).to be_present
    end

    it 'reuses existing release for same version/environment' do
      # Pre-create a release for this project/version/environment
      existing_release = ActsAsTenant.with_tenant(account) do
        create(
          :release,
          project: project,
          account: account,
          version: 'v1.0.1',
          environment: 'staging'
        )
      end

      body = {
        project_slug: project.slug,
        version: existing_release.version,
        environment: existing_release.environment,
        status: 'success',
        user: user.email,
        started_at: 2.minutes.ago.iso8601,
        finished_at: Time.current.iso8601
      }.to_json

      deploy_count_before  = ActsAsTenant.with_tenant(account) { Deploy.count }
      release_count_before = ActsAsTenant.with_tenant(account) { Release.count }

      post '/api/v1/deploys', params: body, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['ok']).to eq(true)

      expect(ActsAsTenant.with_tenant(account) { Deploy.count }).to eq(deploy_count_before + 1)
      expect(ActsAsTenant.with_tenant(account) { Release.count }).to eq(release_count_before)
    end

    it 'returns not_found for unknown project slug' do
      body = {
        project_slug: 'missing-project',
        version: 'v1.0.0',
        environment: 'production',
        status: 'success',
        user: user.email
      }.to_json

      post '/api/v1/deploys', params: body, headers: headers

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('not_found')
    end

    it 'returns not_found for unknown user email' do
      body = {
        project_slug: project.slug,
        version: 'v1.0.0',
        environment: 'production',
        status: 'success',
        user: 'missing@example.com'
      }.to_json

      post '/api/v1/deploys', params: body, headers: headers

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('not_found')
    end
  end
end
