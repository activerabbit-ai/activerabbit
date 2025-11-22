# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResourceQuotas, type: :model do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include ActiveModel::Model
      include ResourceQuotas

      attr_accessor :id, :current_plan, :event_usage_period_start, :event_usage_period_end

      # Mock associations
      def projects
        @projects ||= double("projects")
      end
    end
  end

  let(:account) { test_class.new(id: 1, current_plan: "team") }

  describe "PLAN_QUOTAS constant" do
    it "defines quotas for all plans" do
      expect(ResourceQuotas::PLAN_QUOTAS).to include(:free, :team, :business)
    end

    it "includes all resource types for each plan" do
      ResourceQuotas::PLAN_QUOTAS.each do |_plan, quotas|
        expect(quotas).to include(:events, :ai_summaries, :pull_requests, :uptime_monitors, :status_pages)
      end
    end
  end

  describe "#event_quota_value" do
    context "when on free plan" do
      before { account.current_plan = "free" }

      it "returns 3,000" do
        expect(account.event_quota_value).to eq(3_000)
      end
    end

    context "when on team plan" do
      before { account.current_plan = "team" }

      it "returns 50,000" do
        expect(account.event_quota_value).to eq(50_000)
      end
    end

    context "when on business plan" do
      before { account.current_plan = "business" }

      it "returns 50,000" do
        expect(account.event_quota_value).to eq(50_000)
      end
    end

    context "when plan is unknown" do
      before { account.current_plan = "unknown" }

      it "defaults to free plan quota" do
        expect(account.event_quota_value).to eq(3_000)
      end
    end

    context "when plan name has different casing" do
      it "handles uppercase" do
        account.current_plan = "TEAM"
        expect(account.event_quota_value).to eq(50_000)
      end

      it "handles mixed case" do
        account.current_plan = "Team"
        expect(account.event_quota_value).to eq(50_000)
      end
    end
  end

  describe "#ai_summaries_quota" do
    it "returns 5 for free plan" do
      account.current_plan = "free"
      expect(account.ai_summaries_quota).to eq(5)
    end

    it "returns 50 for team plan" do
      account.current_plan = "team"
      expect(account.ai_summaries_quota).to eq(50)
    end

    it "returns 100 for business plan" do
      account.current_plan = "business"
      expect(account.ai_summaries_quota).to eq(100)
    end
  end

  describe "#pull_requests_quota" do
    it "returns 5 for free plan" do
      account.current_plan = "free"
      expect(account.pull_requests_quota).to eq(5)
    end

    it "returns 10 for team plan" do
      account.current_plan = "team"
      expect(account.pull_requests_quota).to eq(10)
    end

    it "returns 20 for business plan" do
      account.current_plan = "business"
      expect(account.pull_requests_quota).to eq(20)
    end
  end

  describe "#uptime_monitors_quota" do
    it "returns correct quota for each plan" do
      {
        "free" => 1,
        "team" => 5,
        "business" => 5
      }.each do |plan, expected_quota|
        account.current_plan = plan
        expect(account.uptime_monitors_quota).to eq(expected_quota)
      end
    end
  end

  describe "#status_pages_quota" do
    it "returns 1 for all plans" do
      %w[free team business].each do |plan|
        account.current_plan = plan
        expect(account.status_pages_quota).to eq(1)
      end
    end
  end

  describe "#within_quota?" do
    before do
      account.current_plan = "team"
      allow(account).to receive(:events_used_in_billing_period).and_return(25_000)
      allow(account).to receive(:ai_summaries_used_in_period).and_return(45)
      allow(account).to receive(:pull_requests_used_in_period).and_return(5)
    end

    context "when under quota" do
      it "returns true for events" do
        expect(account.within_quota?(:events)).to be true
      end

      it "returns true for ai_summaries" do
        expect(account.within_quota?(:ai_summaries)).to be true
      end

      it "returns true for pull_requests" do
        expect(account.within_quota?(:pull_requests)).to be true
      end
    end

    context "when at quota limit" do
      before do
        allow(account).to receive(:ai_summaries_used_in_period).and_return(50)
      end

      it "returns false" do
        expect(account.within_quota?(:ai_summaries)).to be false
      end
    end

    context "when over quota" do
      before do
        allow(account).to receive(:events_used_in_billing_period).and_return(60_000)
      end

      it "returns false" do
        expect(account.within_quota?(:events)).to be false
      end
    end

    context "with invalid resource type" do
      it "returns false" do
        expect(account.within_quota?(:invalid_resource)).to be false
      end
    end
  end

  describe "#usage_percentage" do
    before do
      account.current_plan = "team"
    end

    context "when usage is 50%" do
      before do
        allow(account).to receive(:ai_summaries_used_in_period).and_return(25)
      end

      it "returns 50.0" do
        expect(account.usage_percentage(:ai_summaries)).to eq(50.0)
      end
    end

    context "when usage is 0%" do
      before do
        allow(account).to receive(:pull_requests_used_in_period).and_return(0)
      end

      it "returns 0.0" do
        expect(account.usage_percentage(:pull_requests)).to eq(0.0)
      end
    end

    context "when usage is over 100%" do
      before do
        allow(account).to receive(:ai_summaries_used_in_period).and_return(75)
      end

      it "returns percentage over 100" do
        expect(account.usage_percentage(:ai_summaries)).to eq(150.0)
      end
    end

    context "when quota is zero" do
      before do
        allow(account).to receive(:event_quota_value).and_return(0)
      end

      it "returns 0.0" do
        expect(account.usage_percentage(:events)).to eq(0.0)
      end
    end

    context "with invalid resource type" do
      it "returns 0.0" do
        expect(account.usage_percentage(:invalid_resource)).to eq(0.0)
      end
    end
  end

  describe "#usage_summary" do
    before do
      account.current_plan = "team"
      allow(account).to receive(:events_used_in_billing_period).and_return(10_000)
      allow(account).to receive(:ai_summaries_used_in_period).and_return(25)
      allow(account).to receive(:pull_requests_used_in_period).and_return(3)
      allow(account).to receive(:uptime_monitors_used).and_return(2)
      allow(account).to receive(:status_pages_used).and_return(1)
    end

    it "returns a hash with all resource types" do
      summary = account.usage_summary
      expect(summary.keys).to contain_exactly(:events, :ai_summaries, :pull_requests, :uptime_monitors, :status_pages)
    end

    it "includes quota for each resource" do
      summary = account.usage_summary
      expect(summary[:events][:quota]).to eq(50_000)
      expect(summary[:ai_summaries][:quota]).to eq(50)
      expect(summary[:pull_requests][:quota]).to eq(10)
    end

    it "includes used count for each resource" do
      summary = account.usage_summary
      expect(summary[:events][:used]).to eq(10_000)
      expect(summary[:ai_summaries][:used]).to eq(25)
      expect(summary[:pull_requests][:used]).to eq(3)
    end

    it "calculates remaining for each resource" do
      summary = account.usage_summary
      expect(summary[:events][:remaining]).to eq(40_000)
      expect(summary[:ai_summaries][:remaining]).to eq(25)
      expect(summary[:pull_requests][:remaining]).to eq(7)
    end

    it "includes percentage for each resource" do
      summary = account.usage_summary
      expect(summary[:events][:percentage]).to eq(20.0)
      expect(summary[:ai_summaries][:percentage]).to eq(50.0)
      expect(summary[:pull_requests][:percentage]).to eq(30.0)
    end

    it "includes within_quota flag for each resource" do
      summary = account.usage_summary
      expect(summary[:events][:within_quota]).to be true
      expect(summary[:ai_summaries][:within_quota]).to be true
      expect(summary[:pull_requests][:within_quota]).to be true
    end

    context "when over quota" do
      before do
        allow(account).to receive(:ai_summaries_used_in_period).and_return(60)
      end

      it "shows remaining as 0" do
        summary = account.usage_summary
        expect(summary[:ai_summaries][:remaining]).to eq(0)
      end

      it "sets within_quota to false" do
        summary = account.usage_summary
        expect(summary[:ai_summaries][:within_quota]).to be false
      end
    end
  end

  describe "billing period helpers" do
    context "when billing period is set" do
      let(:start_date) { Time.zone.parse("2024-01-01") }
      let(:end_date) { Time.zone.parse("2024-01-31") }

      before do
        account.event_usage_period_start = start_date
        account.event_usage_period_end = end_date
      end

      it "uses the set billing period" do
        expect(account.send(:billing_period_start)).to eq(start_date)
        expect(account.send(:billing_period_end)).to eq(end_date)
      end
    end

    context "when billing period is not set" do
      before do
        account.event_usage_period_start = nil
        account.event_usage_period_end = nil
      end

      it "defaults to current month" do
        expect(account.send(:billing_period_start)).to eq(Time.current.beginning_of_month)
        expect(account.send(:billing_period_end)).to eq(Time.current.end_of_month)
      end
    end
  end
end
