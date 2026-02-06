# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Devise routes", type: :routing do
  # NOTE: With devise_for :users, path: "", routes are at root level
  # e.g., /confirmation instead of /users/confirmation

  describe "confirmation routes" do
    it "routes GET /confirmation to devise confirmations#show" do
      expect(get: "/confirmation").to route_to(
        controller: "devise/confirmations",
        action: "show"
      )
    end

    it "routes POST /confirmation to devise confirmations#create" do
      expect(post: "/confirmation").to route_to(
        controller: "devise/confirmations",
        action: "create"
      )
    end

    it "routes GET /confirmation/new to devise confirmations#new" do
      expect(get: "/confirmation/new").to route_to(
        controller: "devise/confirmations",
        action: "new"
      )
    end
  end

  describe "users resource routes" do
    it "routes GET /users/123 to users#show (numeric ID)" do
      expect(get: "/users/123").to route_to(
        controller: "users",
        action: "show",
        id: "123"
      )
    end

    it "does NOT route GET /users/confirmation to users#show" do
      # With path: "", confirmation routes are at /confirmation, not /users/confirmation
      # /users/confirmation would match users resource if not constrained to numeric IDs
      expect(get: "/users/confirmation").not_to be_routable
    end
  end

  describe "session routes" do
    it "routes GET /signin to devise sessions#new" do
      expect(get: "/signin").to route_to(
        controller: "devise/sessions",
        action: "new"
      )
    end

    it "routes GET /signout to devise sessions#destroy" do
      expect(delete: "/signout").to route_to(
        controller: "devise/sessions",
        action: "destroy"
      )
    end

    it "routes GET /signup to devise registrations#new" do
      expect(get: "/signup").to route_to(
        controller: "devise/registrations",
        action: "new"
      )
    end
  end
end
