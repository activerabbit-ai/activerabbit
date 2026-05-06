require "rails_helper"

RSpec.describe Sentry::ImportProjectJob, type: :job do
  it "calls Sentry::ImportService.call with the project" do
    project = double("Project", id: 1)
    allow(Project).to receive(:find).with(1).and_return(project)
    expect(Sentry::ImportService).to receive(:call).with(project)
    described_class.perform_now(1)
  end
end
