require "octokit"

module Github
  class SourceFetcher
    def initialize(project:, sha:)
      @project = project
      @sha = sha
    end

    def client
      token = @project.settings["github_pat"]

      @client ||= Octokit::Client.new(
        access_token: token
      )
    end

    def fetch(path)
      client.contents(
        repo,
        path: path,
        ref: @sha
      )
    end

    private

    def repo
      @project.settings["github_repo"]
    end
  end
end
