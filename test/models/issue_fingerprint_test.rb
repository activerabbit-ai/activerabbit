require "test_helper"

class IssueFingerprintTest < ActiveSupport::TestCase
  # generate_fingerprint - standard fingerprinting

  test "generates same fingerprint for same error details" do
    fp1 = Issue.send(:generate_fingerprint,
      "RuntimeError",
      "app/services/payment_service.rb:42",
      "PaymentsController#create"
    )
    fp2 = Issue.send(:generate_fingerprint,
      "RuntimeError",
      "app/services/payment_service.rb:42",
      "PaymentsController#create"
    )

    assert_equal fp1, fp2
  end

  test "generates different fingerprints for different exceptions" do
    fp1 = Issue.send(:generate_fingerprint,
      "RuntimeError",
      "app/services/payment_service.rb:42",
      "PaymentsController#create"
    )
    fp2 = Issue.send(:generate_fingerprint,
      "ArgumentError",
      "app/services/payment_service.rb:42",
      "PaymentsController#create"
    )

    refute_equal fp1, fp2
  end

  test "generates different fingerprints for different locations" do
    fp1 = Issue.send(:generate_fingerprint,
      "RuntimeError",
      "app/services/payment_service.rb:42",
      "PaymentsController#create"
    )
    fp2 = Issue.send(:generate_fingerprint,
      "RuntimeError",
      "app/services/order_service.rb:100",
      "PaymentsController#create"
    )

    refute_equal fp1, fp2
  end

  test "normalizes line numbers" do
    fp1 = Issue.send(:generate_fingerprint,
      "RuntimeError",
      "app/services/payment_service.rb:42",
      "PaymentsController#create"
    )
    fp2 = Issue.send(:generate_fingerprint,
      "RuntimeError",
      "app/services/payment_service.rb:100",
      "PaymentsController#create"
    )

    assert_equal fp1, fp2
  end

  # origin-based fingerprinting for common exceptions

  test "groups RecordNotFound by originating code location" do
    fp1 = Issue.send(:generate_fingerprint,
      "ActiveRecord::RecordNotFound",
      "app/controllers/base_controller.rb:42",
      "Reports::HoursController#index"
    )
    fp2 = Issue.send(:generate_fingerprint,
      "ActiveRecord::RecordNotFound",
      "app/controllers/base_controller.rb:100",
      "Reports::TasksController#index"
    )

    assert_equal fp1, fp2
  end

  test "separates RecordNotFound from different files" do
    fp1 = Issue.send(:generate_fingerprint,
      "ActiveRecord::RecordNotFound",
      "app/controllers/jobs_controller.rb:42",
      "JobsController#show"
    )
    fp2 = Issue.send(:generate_fingerprint,
      "ActiveRecord::RecordNotFound",
      "app/controllers/companies_controller.rb:42",
      "CompaniesController#show"
    )

    refute_equal fp1, fp2
  end

  test "ORIGIN_BASED_FINGERPRINT_EXCEPTIONS includes common exceptions" do
    assert_includes Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS, "ActiveRecord::RecordNotFound"
    assert_includes Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS, "ActionController::RoutingError"
    assert_includes Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS, "ActionController::UnknownFormat"
    assert_includes Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS, "ActionController::InvalidAuthenticityToken"
    assert_includes Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS, "ActionController::ParameterMissing"
  end

  # find_or_create_by_fingerprint

  test "groups RecordNotFound from same originating code location" do
    project = projects(:default)

    issue1 = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/reports/base_controller.rb:214",
      controller_action: "Reports::HoursController#index",
      sample_message: "Couldn't find Organization"
    )

    issue2 = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/reports/base_controller.rb:214",
      controller_action: "Reports::TasksController#index",
      sample_message: "Couldn't find Organization"
    )

    assert_equal issue1.id, issue2.id
    assert_equal 2, issue2.count
  end

  test "separates RecordNotFound from different originating files" do
    project = projects(:default)

    issue1 = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/jobs_controller.rb:42",
      controller_action: "JobsController#show",
      sample_message: "can't find record"
    )

    issue2 = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/companies_controller.rb:100",
      controller_action: "CompaniesController#show",
      sample_message: "can't find record"
    )

    refute_equal issue1.id, issue2.id
  end

  test "standard exceptions still use controller action" do
    project = projects(:default)

    issue1 = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "RuntimeError",
      top_frame: "app/controllers/base_controller.rb:50",
      controller_action: "UsersController#show"
    )

    issue2 = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "RuntimeError",
      top_frame: "app/controllers/base_controller.rb:50",
      controller_action: "ProjectsController#index"
    )

    refute_equal issue1.id, issue2.id
  end
end
