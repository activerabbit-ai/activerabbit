require 'rails_helper'

RSpec.describe 'API::V1::Releases', type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user, account: user.account) }
  let(:token) { create(:api_token, project: project, account: user.account) }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Project-Token' => token.token } }

  describe 'POST /api/v1/releases' do
    it 'creates a release' do
      body = { version: 'v1.2.3', environment: 'production' }.to_json
      post '/api/v1/releases', params: body, headers: headers
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['version']).to eq('v1.2.3')
    end

    it 'conflicts on duplicate' do
      post '/api/v1/releases', params: { version: 'v1.0.0' }.to_json, headers: headers
      post '/api/v1/releases', params: { version: 'v1.0.0' }.to_json, headers: headers
      expect(response).to have_http_status(:conflict)
    end
  end

  describe 'GET /api/v1/releases' do
    it 'lists releases' do
      create(:release, project: project, account: project.account, version: 'v1')
      get '/api/v1/releases', headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.first['version']).to eq('v1')
    end
  end

  describe 'GET /api/v1/releases/:id' do
    it 'shows a release' do
      rel = create(:release, project: project, account: project.account, version: 'v2')
      get "/api/v1/releases/#{rel.id}", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['version']).to eq('v2')
    end
  end

  describe 'POST /api/v1/releases/:id/trigger_regression_check' do
    it 'queues regression check' do
      rel = create(:release, project: project, account: project.account, version: 'v3')
      post "/api/v1/releases/#{rel.id}/trigger_regression_check", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['message']).to match(/queued/i)
    end
  end
end



