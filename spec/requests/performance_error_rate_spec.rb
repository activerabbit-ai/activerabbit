# require "rails_helper"

# RSpec.describe "Performance error rate", type: :request do
#   # This suite uses `spec/support/acts_as_tenant.rb` which sets a tenant account
#   # before each example. Use that tenant so all created records are visible under
#   # ActsAsTenant scoping.
#   let(:account) { ActsAsTenant.current_tenant || create(:account) }
#   let(:user) do
#     create(:user, account: account).tap do |u|
#       # Force correct account association if factory/callback behavior overwrites it
#       u.update_column(:account_id, account.id) if u.account_id != account.id
#     end
#   end
#   let!(:project) { create(:project, user: user, account: account) }

#   before do
#     Rails.application.reload_routes!
#     sign_in user
#   end

#   it "does not hardcode 0.0% when there are errors (no rollups present)" do
#     # Ensure we hit the raw-events fallback path by not creating PerfRollup rows
#     create(:performance_event, project: project, target: "HomeController#index", duration_ms: 100.0, occurred_at: 10.minutes.ago)
#     create(:performance_event, project: project, target: "HomeController#index", duration_ms: 110.0, occurred_at: 9.minutes.ago)

#     # Two errors in the events table within 7 days
#     create(:event, project: project, account: account, controller_action: "HomeController#index", occurred_at: 8.minutes.ago)
#     create(:event, project: project, account: account, controller_action: "HomeController#index", occurred_at: 7.minutes.ago)

#     get "/projects/#{project.id}/performance"
#     expect(response).to have_http_status(:ok)

#     # 2 errors / 2 requests => 100.0%
#     expect(response.body).to include("Error Rate")
#     expect(response.body).to match(/100(\.0+)?%/)
#     expect(response.body).not_to include("0.0%")
#   end
# end
