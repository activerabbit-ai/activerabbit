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

    describe 'coarse fingerprinting for noise exceptions' do
      it 'groups RecordNotFound by controller only' do
        # Same controller, different actions
        fp1 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/jobs_controller.rb:42',
          'JobsController#show'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActiveRecord::RecordNotFound',
          'app/controllers/jobs_controller.rb:100',
          'JobsController#index'
        )

        expect(fp1).to eq(fp2) # Same controller -> same fingerprint
      end

      it 'separates RecordNotFound by controller' do
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

        expect(fp1).not_to eq(fp2) # Different controllers -> different fingerprints
      end

      it 'groups RoutingError by controller only' do
        fp1 = Issue.send(:generate_fingerprint,
          'ActionController::RoutingError',
          'somewhere/in/rails.rb:100',
          'ApplicationController#not_found'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActionController::RoutingError',
          'somewhere/else/in/rails.rb:200',
          'ApplicationController#handle_error'
        )

        expect(fp1).to eq(fp2) # Same controller (ApplicationController)
      end

      it 'groups InvalidAuthenticityToken by controller only' do
        fp1 = Issue.send(:generate_fingerprint,
          'ActionController::InvalidAuthenticityToken',
          'somewhere.rb:1',
          'SessionsController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActionController::InvalidAuthenticityToken',
          'elsewhere.rb:99',
          'SessionsController#destroy'
        )

        expect(fp1).to eq(fp2)
      end

      it 'groups ParameterMissing by controller only' do
        fp1 = Issue.send(:generate_fingerprint,
          'ActionController::ParameterMissing',
          'somewhere.rb:1',
          'UsersController#create'
        )
        fp2 = Issue.send(:generate_fingerprint,
          'ActionController::ParameterMissing',
          'elsewhere.rb:99',
          'UsersController#update'
        )

        expect(fp1).to eq(fp2)
      end
    end

    describe 'COARSE_FINGERPRINT_EXCEPTIONS list' do
      it 'includes common noise exceptions' do
        expect(Issue::COARSE_FINGERPRINT_EXCEPTIONS).to include('ActiveRecord::RecordNotFound')
        expect(Issue::COARSE_FINGERPRINT_EXCEPTIONS).to include('ActionController::RoutingError')
        expect(Issue::COARSE_FINGERPRINT_EXCEPTIONS).to include('ActionController::UnknownFormat')
        expect(Issue::COARSE_FINGERPRINT_EXCEPTIONS).to include('ActionController::InvalidAuthenticityToken')
        expect(Issue::COARSE_FINGERPRINT_EXCEPTIONS).to include('ActionController::ParameterMissing')
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

    it 'groups RecordNotFound from same controller' do
      issue1 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/jobs_controller.rb:42',
        controller_action: 'JobsController#show',
        sample_message: "can't find record with friendly id: \"feed\""
      )

      issue2 = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'ActiveRecord::RecordNotFound',
        top_frame: 'app/controllers/jobs_controller.rb:100',
        controller_action: 'JobsController#index',
        sample_message: "can't find record with friendly id: \"centerbase\""
      )

      expect(issue1.id).to eq(issue2.id) # Same issue!
      expect(issue2.count).to eq(2)
    end
  end
end

