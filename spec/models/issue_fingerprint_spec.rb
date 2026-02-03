require 'rails_helper'

RSpec.describe Issue, 'fingerprint generation', type: :model do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '.generate_fingerprint' do
    describe 'standard fingerprinting' do
      it 'generates same fingerprint for same error details' do
        fp1 = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/payment_service.rb:42',
          'PaymentsController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/payment_service.rb:42',
          'PaymentsController#create'
        )

        expect(fp1).to eq(fp2)
      end

      it 'generates different fingerprints for different exceptions' do
        fp1 = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/payment_service.rb:42',
          'PaymentsController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ArgumentError',
          'app/services/payment_service.rb:42',
          'PaymentsController#create'
        )

        expect(fp1).not_to eq(fp2)
      end

      it 'generates different fingerprints for different locations' do
        fp1 = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/payment_service.rb:42',
          'PaymentsController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/order_service.rb:100',
          'PaymentsController#create'
        )

        expect(fp1).not_to eq(fp2)
      end

      it 'normalizes line numbers' do
        fp1 = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/payment_service.rb:42',
          'PaymentsController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'RuntimeError',
          'app/services/payment_service.rb:100', # Different line number
          'PaymentsController#create'
        )

        expect(fp1).to eq(fp2)
      end
    end

    describe 'origin-based fingerprinting for common exceptions' do
      it 'groups RecordNotFound by originating code location (same file = same fingerprint)' do
        # Same originating file, different line numbers → same fingerprint (line numbers normalized)
        fp1 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/base_controller.rb:42',
          'Reports::HoursController#index'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/base_controller.rb:100', # Different line (but same file)
          'Reports::TasksController#index' # Different controller - doesn't matter!
        )

        expect(fp1).to eq(fp2) # Same origin -> same fingerprint (single bug to fix)
      end

      it 'groups RecordNotFound from same base_controller regardless of entry point' do
        # This is the key case: errors from shared code should be grouped
        fp1 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/reports/base_controller.rb:214',
          'Reports::HoursController#index'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/reports/base_controller.rb:214',
          'Reports::TasksController#index'
        )
        fp3 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/reports/base_controller.rb:214',
          'Reports::ShiftsController#index'
        )

        expect(fp1).to eq(fp2)
        expect(fp2).to eq(fp3) # All 3 grouped together - one fix needed!
      end

      it 'separates RecordNotFound by originating file (different files = different fingerprints)' do
        fp1 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/jobs_controller.rb:42',
          'JobsController#show'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/companies_controller.rb:42',
          'CompaniesController#show'
        )

        expect(fp1).not_to eq(fp2) # Different originating files -> different fingerprints
      end

      it 'groups RoutingError by originating code location' do
        fp1 = Issue.send(:generate_fingerprint,
          'ActionController::RoutingError',
          'somewhere/in/rails.rb:100',
          'ApplicationController#not_found'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActionController::RoutingError',
          'somewhere/in/rails.rb:200', # Same file, different line (normalized)
          'OtherController#handle_error'  # Different action - doesn't matter
        )

        expect(fp1).to eq(fp2) # Same origin -> same fingerprint
      end

      it 'groups InvalidAuthenticityToken by originating code location' do
        fp1 = Issue.send(:generate_fingerprint,
          'ActionController::InvalidAuthenticityToken',
          'somewhere.rb:1',
          'SessionsController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActionController::InvalidAuthenticityToken',
          'somewhere.rb:99', # Same file
          'ApiController#authenticate' # Different action
        )

        expect(fp1).to eq(fp2)
      end

      it 'groups ParameterMissing by originating code location' do
        fp1 = Issue.send(:generate_fingerprint,
          'ActionController::ParameterMissing',
          'somewhere.rb:1',
          'UsersController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActionController::ParameterMissing',
          'somewhere.rb:99', # Same file
          'UsersController#update' # Different action
        )

        expect(fp1).to eq(fp2)
      end
    end

    describe 'ORIGIN_BASED_FINGERPRINT_EXCEPTIONS list' do
      it 'includes common exceptions that should be grouped by origin' do
        expect(Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS).to include('ActiveRecord::RecordNotFound')
        expect(Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS).to include('ActionController::RoutingError')
        expect(Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS).to include('ActionController::UnknownFormat')
        expect(Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS).to include('ActionController::InvalidAuthenticityToken')
        expect(Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS).to include('ActionController::ParameterMissing')
      end
    end
  end

  describe '.find_or_create_by_fingerprint' do
    it 'creates issue with correct fingerprint' do
      issue = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'RuntimeError',
        top_frame: 'app/services/test.rb:42',
        controller_action: 'TestController#action',
        sample_message: 'Something went wrong'
      )

      expect(issue).to be_persisted
      expect(issue.fingerprint).to be_present
    end

    it 'finds existing issue by fingerprint' do
      issue1 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'RuntimeError',
        top_frame: 'app/services/test.rb:42',
        controller_action: 'TestController#action'
      )

      issue2 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'RuntimeError',
        top_frame: 'app/services/test.rb:42',
        controller_action: 'TestController#action'
      )

      expect(issue1.id).to eq(issue2.id)
      expect(issue2.count).to eq(2)
    end

    it 'groups RecordNotFound from same originating code location' do
      # Same origin (base_controller), different controllers → same issue
      issue1 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/reports/base_controller.rb:214',
        controller_action: 'Reports::HoursController#index',
        sample_message: "Couldn't find Organization with 'id'=10"
      )

      issue2 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/reports/base_controller.rb:214', # Same origin
        controller_action: 'Reports::TasksController#index', # Different controller - grouped!
        sample_message: "Couldn't find Organization with 'id'=10"
      )

      issue3 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/reports/base_controller.rb:214', # Same origin
        controller_action: 'Reports::ShiftsController#index', # Different controller - grouped!
        sample_message: "Couldn't find Organization with 'id'=10"
      )

      expect(issue1.id).to eq(issue2.id) # Same issue! (single root cause)
      expect(issue2.id).to eq(issue3.id) # All 3 grouped together
      expect(issue3.count).to eq(3)
    end

    it 'separates RecordNotFound from different originating files' do
      issue1 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/jobs_controller.rb:42',
        controller_action: 'JobsController#show',
        sample_message: "can't find record"
      )

      issue2 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/companies_controller.rb:100', # Different file
        controller_action: 'CompaniesController#show',
        sample_message: "can't find record"
      )

      expect(issue1.id).not_to eq(issue2.id) # Different origins -> different issues
    end
  end

  describe 'error grouping scenarios' do
    describe 'base controller inheritance pattern' do
      # Real-world scenario: Multiple report controllers inherit from Reports::BaseController
      # An error in authenticate_with_bearer_token should be grouped regardless of which
      # child controller was the entry point

      it 'groups errors from shared base controller across all child controllers' do
        controllers = [
          'Reports::HoursController#index',
          'Reports::TasksController#index',
          'Reports::ShiftsController#index',
          'Reports::AttendanceController#show',
          'Reports::ScheduleController#export'
        ]

        issues = controllers.map do |controller_action|
          Issue.find_or_create_by_fingerprint(
            project: project,
            exception_class: 'ActiveRecord::RecordNotFound',
            top_frame: 'app/controllers/reports/base_controller.rb:214',
            controller_action: controller_action,
            sample_message: "Couldn't find Organization with 'id'=10"
          )
        end

        # All 5 errors should be the same issue
        expect(issues.map(&:id).uniq.size).to eq(1)
        expect(issues.last.count).to eq(5)
      end

      it 'groups errors from ApplicationController used by many controllers' do
        controllers = [
          'UsersController#show',
          'ProjectsController#index',
          'DashboardController#home',
          'SettingsController#edit'
        ]

        issues = controllers.map do |controller_action|
          Issue.find_or_create_by_fingerprint(
            project: project,
            exception_class: 'ActiveRecord::RecordNotFound',
            top_frame: 'app/controllers/application_controller.rb:45',
            controller_action: controller_action,
            sample_message: "Couldn't find Account"
          )
        end

        expect(issues.map(&:id).uniq.size).to eq(1)
        expect(issues.last.count).to eq(4)
      end
    end

    describe 'shared concerns pattern' do
      it 'groups errors from a concern included in multiple controllers' do
        # Authenticatable concern included in API and Web controllers
        controllers = [
          'Api::V1::UsersController#index',
          'Api::V1::ProjectsController#show',
          'Web::DashboardController#index'
        ]

        issues = controllers.map do |controller_action|
          Issue.find_or_create_by_fingerprint(
            project: project,
            exception_class: 'ActiveRecord::RecordNotFound',
            top_frame: 'app/controllers/concerns/authenticatable.rb:32',
            controller_action: controller_action,
            sample_message: "Couldn't find User"
          )
        end

        expect(issues.map(&:id).uniq.size).to eq(1)
      end
    end

    describe 'service object pattern' do
      it 'groups errors from service called by multiple controllers' do
        # PaymentService called from different controllers
        controllers = [
          'CheckoutController#create',
          'SubscriptionsController#update',
          'Api::PaymentsController#process'
        ]

        issues = controllers.map do |controller_action|
          Issue.find_or_create_by_fingerprint(
            project: project,
            exception_class: 'ActiveRecord::RecordNotFound',
            top_frame: 'app/services/payment_service.rb:88',
            controller_action: controller_action,
            sample_message: "Couldn't find PaymentMethod"
          )
        end

        expect(issues.map(&:id).uniq.size).to eq(1)
      end
    end

    describe 'different exception types remain separate' do
      it 'does not group different exception types even from same location' do
        issue1 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show'
        )

        issue2 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordInvalid',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show'
        )

        expect(issue1.id).not_to eq(issue2.id)
      end
    end

    describe 'different originating files remain separate' do
      it 'separates RecordNotFound from different base controllers' do
        issue1 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/api/base_controller.rb:30',
          controller_action: 'Api::UsersController#show'
        )

        issue2 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/web/base_controller.rb:30',
          controller_action: 'Web::UsersController#show'
        )

        expect(issue1.id).not_to eq(issue2.id)
      end

      it 'separates RecordNotFound from different methods in same file' do
        # Different methods in same file should be grouped (line numbers normalized)
        # This tests that we're grouping by FILE, not by exact line
        issue1 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show'
        )

        issue2 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:120',
          controller_action: 'ProjectsController#index'
        )

        # Same file → same issue (line numbers are normalized)
        expect(issue1.id).to eq(issue2.id)
      end
    end

    describe 'standard exceptions still use controller action' do
      it 'separates standard errors by controller action' do
        # Non-origin-based exceptions should still separate by controller
        issue1 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'RuntimeError',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'UsersController#show'
        )

        issue2 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'RuntimeError',
          top_frame: 'app/controllers/base_controller.rb:50',
          controller_action: 'ProjectsController#index'
        )

        expect(issue1.id).not_to eq(issue2.id)
      end
    end

    describe 'all ORIGIN_BASED exceptions are properly grouped' do
      Issue::ORIGIN_BASED_FINGERPRINT_EXCEPTIONS.each do |exception_class|
        it "groups #{exception_class} by originating code location" do
          issue1 = Issue.find_or_create_by_fingerprint(
            project: project,
            exception_class: exception_class,
            top_frame: 'app/controllers/shared/auth.rb:25',
            controller_action: 'FirstController#action1'
          )

          issue2 = Issue.find_or_create_by_fingerprint(
            project: project,
            exception_class: exception_class,
            top_frame: 'app/controllers/shared/auth.rb:99',
            controller_action: 'SecondController#action2'
          )

          expect(issue1.id).to eq(issue2.id),
            "Expected #{exception_class} to be grouped by origin, but got separate issues"
        end
      end
    end

    describe 'real-world Rescuehub scenario' do
      # Exact scenario from user: 3 errors from Reports controllers
      # all originating from authenticate_with_bearer_token in base_controller

      it 'groups the 3 Rescuehub RecordNotFound errors into 1 issue' do
        # Error 1: Reports::HoursController#index
        issue1 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: '/var/app/current/app/controllers/reports/base_controller.rb:214',
          controller_action: 'Reports::HoursController#index',
          sample_message: "Couldn't find Organization with 'id'=10 [WHERE \"memberships\".\"user_id\" = $1 AND ...]"
        )

        # Error 2: Reports::TasksController#index
        issue2 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: '/var/app/current/app/controllers/reports/base_controller.rb:214',
          controller_action: 'Reports::TasksController#index',
          sample_message: "Couldn't find Organization with 'id'=10 [WHERE \"memberships\".\"user_id\" = $1 AND ...]"
        )

        # Error 3: Another Reports controller (hypothetical 3rd error mentioned by user)
        issue3 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: '/var/app/current/app/controllers/reports/base_controller.rb:214',
          controller_action: 'Reports::ShiftsController#index',
          sample_message: "Couldn't find Organization with 'id'=10 [WHERE \"memberships\".\"user_id\" = $1 AND ...]"
        )

        # All should be ONE issue
        expect(issue1.id).to eq(issue2.id)
        expect(issue2.id).to eq(issue3.id)
        expect(issue3.count).to eq(3)

        # Verify only 1 issue was created
        expect(Issue.where(project: project, exception_class: 'ActiveRecord::RecordNotFound').count).to eq(1)
      end
    end

    describe 'issue count tracking' do
      it 'correctly counts occurrences across grouped errors' do
        10.times do |i|
          Issue.find_or_create_by_fingerprint(
            project: project,
            exception_class: 'ActiveRecord::RecordNotFound',
            top_frame: 'app/controllers/base_controller.rb:100',
            controller_action: "Controller#{i}#action",
            sample_message: "Error #{i}"
          )
        end

        issues = Issue.where(project: project, exception_class: 'ActiveRecord::RecordNotFound')
        expect(issues.count).to eq(1)
        expect(issues.first.count).to eq(10)
      end
    end

    describe 'cross-project isolation' do
      let(:other_project) { create(:project, account: account) }

      it 'does not group errors across different projects' do
        issue1 = Issue.find_or_create_by_fingerprint(
          project: project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:100',
          controller_action: 'UsersController#show'
        )

        issue2 = Issue.find_or_create_by_fingerprint(
          project: other_project,
          exception_class: 'ActiveRecord::RecordNotFound',
          top_frame: 'app/controllers/base_controller.rb:100',
          controller_action: 'UsersController#show'
        )

        expect(issue1.id).not_to eq(issue2.id)
        expect(issue1.project_id).to eq(project.id)
        expect(issue2.project_id).to eq(other_project.id)
      end
    end
  end
end
