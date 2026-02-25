# frozen_string_literal: true

module Api
  module V1
    module Cli
      class BaseController < Api::BaseController
        # CLI endpoints use the same X-Project-Token auth as other API endpoints.
        # The token identifies the project (app) and sets the tenant.

        private

        def current_app
          @current_project
        end

        def find_app_by_slug!(slug)
          # Allow finding by slug or ID within the current tenant
          project = Project.find_by(slug: slug) || Project.find_by(id: slug)
          unless project
            render json: { error: "not_found", message: "App not found: #{slug}" }, status: :not_found
            return nil
          end
          project
        end

        def render_cli_response(command:, data:, project: nil)
          render json: {
            project: project&.slug || current_app&.slug,
            generated_at: Time.current.utc.iso8601,
            command: command,
            data: data
          }
        end
      end
    end
  end
end
