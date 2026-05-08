module Sentry
  class ImportProjectJob < ApplicationJob
    queue_as :default

    def perform(project_id)
      project = Project.find(project_id)
      Sentry::ImportService.call(project)
    end
  end
end
