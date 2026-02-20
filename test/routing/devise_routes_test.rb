require "test_helper"

class DeviseRoutesTest < ActionDispatch::IntegrationTest
  # NOTE: With devise_for :users, path: "", routes are at root level
  # e.g., /confirmation instead of /users/confirmation

  # confirmation routes

  test "GET /confirmation routes to devise confirmations#show" do
    assert_routing(
      { method: :get, path: "/confirmation" },
      { controller: "devise/confirmations", action: "show" }
    )
  end

  test "POST /confirmation routes to devise confirmations#create" do
    assert_routing(
      { method: :post, path: "/confirmation" },
      { controller: "devise/confirmations", action: "create" }
    )
  end

  test "GET /confirmation/new routes to devise confirmations#new" do
    assert_routing(
      { method: :get, path: "/confirmation/new" },
      { controller: "devise/confirmations", action: "new" }
    )
  end

  # users resource routes

  test "GET /users/123 routes to users#show with numeric ID" do
    assert_routing(
      { method: :get, path: "/users/123" },
      { controller: "users", action: "show", id: "123" }
    )
  end

  test "GET /users/confirmation is not routable" do
    # With path: "", confirmation routes are at /confirmation, not /users/confirmation
    # Verify this path doesn't route to users#show (it should raise RoutingError)
    error = assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/users/confirmation", method: :get)
    end
    assert_match(/No route matches/, error.message)
  end

  # session routes

  test "GET /signin routes to devise sessions#new" do
    assert_routing(
      { method: :get, path: "/signin" },
      { controller: "devise/sessions", action: "new" }
    )
  end

  test "DELETE /signout routes to devise sessions#destroy" do
    assert_routing(
      { method: :delete, path: "/signout" },
      { controller: "devise/sessions", action: "destroy" }
    )
  end

  test "GET /signup routes to devise registrations#new" do
    assert_routing(
      { method: :get, path: "/signup" },
      { controller: "users/registrations", action: "new" }
    )
  end
end
