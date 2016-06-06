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
        error!("No pipeline specified in project.") unless pipeline
        success = trigger_build(pipeline, git_ref)
        info("Kicked off a build for '#{pipeline}' at ref '#{git_ref}'.") if success
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
        self.http_response = response

        # Filter out events and parse the response
        handle "received github event #{request.params["payload"]}" do
          payload = JSON.parse(request.params["payload"])
          repository = payload["repository"]["name"]
          event_type = request.env["HTTP_X_GITHUB_EVENT"]

          self.project_name = projects.keys.find do |name|
            repo = File.basename(projects[name][:github_url])
            repo = repo[0..-4] if repo.end_with?(".git")
            repo == repository
          end

          if project_name.nil?
            error!("Repository '#{repository}' is not monitored by versioner!")
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

          # Bump the build in a new handler so we get a good title
          parent = self
          versioner = Versioner.new(robot)
          versioner.handle "github merged pull request #{pull_request_url} for #{project_name}: #{merge_commit_sha}" do
            self.http_response = response
            self.project_name = parent.project_name
            bump_version_and_trigger_build
          end
        end
      end

      def bump_version_and_trigger_build
        new_version = bump_version_in_git
        info("Bumped version to #{new_version}")
        git_ref = "v#{new_version}"
        success = trigger_build(project[:pipeline], git_ref)
        info("Kicked off release build for '#{project[:pipeline]}' at ref '#{git_ref}'.") if success
      end

      def bump_version_in_git
        project_repo.bump_version
        project_repo.tag_and_commit

        # we return the version we bumped to
        project_repo.read_version
      end

      template_root File.expand_path("../../templates", __FILE__)
      Lita.register_handler(self)
    end
  end
end
