require "json"
require "uri"
require_relative "../project_repo"
require_relative "bumpbot_handler"

module Lita
  module Handlers
    class Versioner < BumpbotHandler

      # Incoming github events
      http.post "/github_handler", :github_handler

      #
      # User commands
      #
      command_route "build", :build, {
        "[GIT_REF]" => "Kicks off a build for PROJECT with TAG. TAG default: master.",
      }, 1
      command_route "bump", :bump_version_and_trigger_build, {
        "" => "Bumps the version of PROJECT and starts a build.",
      }

      def build
        git_ref = command_args.first || "master"
        pipeline =
          if git_ref == "master"
            project[:pipeline]
          else
            "#{project_name}-trigger-ad_hoc"
          end
        error!("No pipeline specified in project.") unless pipeline
        success = trigger_build(pipeline, git_ref)
        info("Kicked off a build for '#{pipeline}' at ref '#{git_ref}'.") if success
      end

      #
      # Handle incoming github events
      #
      def github_handler(request, response)
        handle_event "github event" do
          payload = JSON.parse(request.params["payload"])

          event_type = request.env["HTTP_X_GITHUB_EVENT"]
          repository = payload["repository"]["full_name"]
          info("Processing '#{event_type}' event for '#{repository}'.")

          self.project_name = projects.each_key.find do |name|
            projects[name][:github_url].match(/.*(\/|:)#{repository}.git/)
          end

          if project_name.nil?
            error!("Repository '#{repository}' is not monitored by versioner!")
          end

          case event_type
          when "pull_request"
            # https://developer.github.com/v3/activity/events/types/#pullrequestevent
            # If the pull request is merged with some commits
            if payload["action"] == "closed"
              if payload["pull_request"]["merged"]
                info("'#{payload["pull_request"]["html_url"]}' was just merged. Bumping version and submitting a build ...")
                bump_version_and_trigger_build
              else
                info("Skipping: '#{payload["pull_request"]["html_url"]}'. It was closed without merging any commits.")
              end
            else
              debug("Skipping: '#{payload["pull_request"]["html_url"]}' Action: '#{payload["action"]}' Merged? '#{payload["pull_request"]["merged"]}'")
            end
          else
            info("Skipping event '#{event_type}' for '#{repository}'. I am only handling 'pull_request' events.")
          end
        end
      end

      def bump_version_and_trigger_build
        new_version = bump_version_in_git
        info("Bumped version to #{new_version}")
        git_ref = "v#{new_version}"
        success = trigger_build(project[:pipeline], git_ref)
        info("Kicked off release build for '#{pipeline}' at ref '#{git_ref}'.") if success
      end

      def bump_version_in_git
        project_repo = ProjectRepo.new(self)
        project_repo.refresh
        project_repo.bump_version
        project_repo.tag_and_commit

        # we return the version we bumped to
        project_repo.read_version
      end
    end

    Lita.register_handler(Versioner)
  end
end
