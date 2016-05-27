require "lita"
require "json"
require "uri"
require_relative "../../lita_versioner/project_repo"
require_relative "bumpbot_handler"

module Lita
  module Handlers
    class Versioner < BumpbotHandler

      # Incoming github events
      http.post "/github_handler", :github_handler

      #
      # User commands
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

      command_route(
        "bump",
        "Bumps the version of PROJECT and starts a build."
      ) do
        bump_version_and_trigger_build
      end

      #
      # Handle incoming github events
      #
      def github_handler(request, response)
        self.http_response = response
        handle_event "github event" do
          payload = JSON.parse(request.params["payload"])
          repository = payload["repository"]["name"]

          self.project_name = projects.each_key.find do |name|
            repo = File.basename(projects[name][:github_url])
            repo = repo[0..-4] if repo.end_with?(".git")
            repo == repository
          end

          if project_name.nil?
            error!("Repository '#{repository}' is not monitored by versioner!")
          end

          event_type = request.env["HTTP_X_GITHUB_EVENT"]

          debug("Processing '#{event_type}' event for '#{repository}'.")

          # https://developer.github.com/v3/activity/events/types/#pullrequestevent
          if event_type != "pull_request"
            debug("Skipping event '#{event_type}' for '#{repository}'. I can only handle 'pull_request' events.")
            return
          end

          # If the pull request is merged with some commits
          if payload["action"] != "closed"
            debug("Skipping: '#{payload["pull_request"]["html_url"]}' Action: '#{payload["action"]}' Merged? '#{payload["pull_request"]["merged"]}'")
            return
          end

          unless payload["pull_request"]["merged"]
            info("Skipping: '#{payload["pull_request"]["html_url"]}'. It was closed without merging any commits.")
            return
          end

          if project_repo.current_sha != payload["pull_request"]["merge_commit_sha"]
            warn("Skipping: '#{payload["pull_request"]["html_url"]}'. Latest master is at SHA #{project_repo.current_sha}, but the pull request merged SHA #{payload["pull_request"]["merge_commit_sha"]}")
            return
          end

          info("'#{payload["pull_request"]["html_url"]}' was just merged. Bumping version and submitting a build ...")
          bump_version_and_trigger_build
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
    end

    Lita.register_handler(Versioner)
  end
end
