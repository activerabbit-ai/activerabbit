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
