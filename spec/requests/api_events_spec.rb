require 'rails_helper'

RSpec.describe 'API::V1::Events', type: :request, api: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, user: user, account: account) }
  let(:token) { create(:api_token, project: project, account: account) }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Project-Token' => token.token } }

  before do
    ActsAsTenant.current_tenant = account
  end

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

    it 'accepts structured_stack_trace with source context' do
      structured_frames = [
        {
          file: "app/controllers/users_controller.rb",
          line: 25,
          method: "show",
          raw: "app/controllers/users_controller.rb:25:in `show'",
          in_app: true,
          frame_type: "controller",
          index: 0,
          source_context: {
            lines_before: ["  def show", "    @user = User.find(params[:id])"],
            line_content: "    raise 'Not found'",
            lines_after: ["  end"],
            start_line: 23
          }
        },
        {
          file: "/gems/actionpack/lib/action_controller.rb",
          line: 100,
          method: "process",
          raw: "/gems/actionpack/lib/action_controller.rb:100:in `process'",
          in_app: false,
          frame_type: "gem",
          index: 1,
          source_context: nil
        }
      ]

      culprit_frame = structured_frames.first

      body = {
        exception_class: 'ArgumentError',
        message: 'User not found',
        backtrace: structured_frames.map { |f| f[:raw] },
        structured_stack_trace: structured_frames,
        culprit_frame: culprit_frame,
        occurred_at: Time.current.iso8601
      }.to_json

      post '/api/v1/events/errors', params: body, headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('created')
    end

    it 'works without structured_stack_trace (backward compatibility)' do
      body = {
        exception_class: 'StandardError',
        message: 'Legacy error',
        backtrace: ["app/models/user.rb:10:in `save'"],
        occurred_at: Time.current.iso8601
      }.to_json

      post '/api/v1/events/errors', params: body, headers: headers

      expect(response).to have_http_status(:created)
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

    it 'accepts controller/action details from metadata' do
      body = {
        name: 'controller.action',
        duration_ms: 87.5,
        metadata: {
          controller: 'HomeController',
          action: 'index',
          method: 'GET',
          path: '/home',
          db_runtime: 12.3,
          view_runtime: 4.2
        }
      }.to_json

      post '/api/v1/events/performance', params: body, headers: headers
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('created')
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
