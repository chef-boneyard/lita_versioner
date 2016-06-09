require "lita"
require "json"
require "uri"
require_relative "../../lita_versioner/project_repo"
require_relative "bumpbot_handler"

module Lita
  module Handlers
    class Versioner < BumpbotHandler

      #
      # Event: github events (https://developer.github.com/v3/activity/events/types/#pullrequestevent)
      #
      http.post "/github_handler", :github_handler

      #
      # Command: build PROJECT [GIT_REF=master]
      #
      command_route(
        "build",
        { "[GIT_REF]" => "Kicks off a build for PROJECT with GIT_REF. GIT_REF default: master." },
        max_args: 1
      ) do |git_ref = "master"|

        if git_ref == "master"
          pipeline = project[:pipeline]
        else
          pipeline = "#{project_name}-trigger-ad_hoc"
        end
        respond_error!("No pipeline specified in project.") unless pipeline
        trigger_build(pipeline, git_ref)
        respond("Kicked off a build for '#{pipeline}' at ref '#{git_ref}'.")
      end

      #
      # Command: bump PROJECT
      #
      command_route(
        "bump",
        "Bumps the version of PROJECT and starts a build."
      ) do
        bump_version_and_trigger_build
      end

      #
      # Helpers (private)
      #

      #
      # Handle incoming github events
      #
      def github_handler(request, response)
        output.http_response = response
        # Filter out events and parse the response
        handle "received github event #{request.params["payload"]}" do
          pull_request_url, merge_commit_sha = parse_github_event(request)
          if pull_request_url
            versioner = Versioner.from_handler(self)
            versioner.handle "github merged pull request #{pull_request_url} for #{project_name}: #{merge_commit_sha}" do
              bump_version_and_trigger_build
            end
          end
        end
      end

      def parse_github_event(request)
        payload = JSON.parse(request.params["payload"])
        repository = payload["repository"]["name"]
        event_type = request.env["HTTP_X_GITHUB_EVENT"]

        self.project_name = projects.keys.find do |name|
          repo = File.basename(projects[name][:github_url])
          repo = repo[0..-4] if repo.end_with?(".git")
          repo == repository
        end

        if project_name.nil?
          respond_error!("Repository '#{repository}' is not monitored by versioner!", http_status_code: "500")
        end

        debug("Processing '#{event_type}' event for '#{repository}'.")

        # https://developer.github.com/v3/activity/events/types/#pullrequestevent
        if event_type != "pull_request"
          debug("Skipping event '#{event_type}' for '#{repository}'. I can only handle 'pull_request' events.")
          return
        end

        pull_request_url = payload["pull_request"]["html_url"]

        # If the pull request is merged with some commits
        if payload["action"] != "closed"
          debug("Skipping: '#{pull_request_url}' Action: '#{payload["action"]}' Merged? '#{payload["pull_request"]["merged"]}'")
          return
        end

        unless payload["pull_request"]["merged"]
          info("Skipping: '#{pull_request_url}'. It was closed without merging any commits.")
          return
        end

        merge_commit_sha = payload["pull_request"]["merge_commit_sha"]

        if project_repo.current_sha != merge_commit_sha
          warn("Skipping: '#{pull_request_url}'. Latest master is at SHA #{project_repo.current_sha}, but the pull request merged SHA #{merge_commit_sha}")
          return
        end

        info("'#{pull_request_url}' was just merged. Bumping version and submitting a build ...")

        [ pull_request_url, merge_commit_sha ]
      end

      def bump_version_and_trigger_build
        project_repo.bump_version
        tag = project_repo.tag_and_commit
        trigger_build(project[:pipeline], tag)
        respond("Bumped version of #{project_name} to <#{project_github_url}/tree/#{tag}|#{tag}> and kicked off a release build.")
        tag
      end

      template_root File.expand_path("../../templates", __FILE__)
      Lita.register_handler(self)
    end
  end
end
