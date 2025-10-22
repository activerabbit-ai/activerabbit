require 'rails_helper'

RSpec.describe 'API::V1::Events', type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user, account: user.account) }
  let(:token) { create(:api_token, project: project, account: user.account) }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Project-Token' => token.token } }

  describe 'POST /api/v1/events/errors' do
    it 'queues error event when valid' do
      body = {
        exception_class: 'RuntimeError',
        message: 'Boom',
        backtrace: ["/app/controllers/home_controller.rb:10:in `index'"],
        occurred_at: Time.current.iso8601
      }.to_json

      post '/api/v1/events/errors', params: body, headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['status']).to eq('created')
    end

    it 'rejects missing fields' do
      body = { message: 'no class' }.to_json
      post '/api/v1/events/errors', params: body, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/events/performance' do
    it 'queues performance event when valid' do
      body = {
        controller_action: 'HomeController#index',
        duration_ms: 250.2,
        occurred_at: Time.current.iso8601
      }.to_json

      post '/api/v1/events/performance', params: body, headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['status']).to eq('created')
    end

    it 'rejects missing duration' do
      body = { controller_action: 'HomeController#index' }.to_json
      post '/api/v1/events/performance', params: body, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/events/batch' do
    it 'accepts mixed events and returns processed_count' do
      body = {
        events: [
          { event_type: 'error', data: { exception_class: 'RuntimeError', message: 'x' } },
          { event_type: 'performance', data: { controller_action: 'HomeController#index', duration_ms: 120.0 } }
        ]
      }.to_json

      post '/api/v1/events/batch', params: body, headers: headers
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['processed_count']).to eq(2)
    end

    it 'rejects empty payload' do
      post '/api/v1/events/batch', params: { events: [] }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/test/connection' do
    it 'returns project context' do
      post '/api/v1/test/connection', headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['project_id']).to eq(project.id)
      expect(json['status']).to eq('success')
    end
  end

  describe 'authentication errors' do
    it 'rejects missing token' do
      post '/api/v1/events/errors', params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects invalid token' do
      post '/api/v1/events/errors', params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Project-Token' => 'bad' }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end



