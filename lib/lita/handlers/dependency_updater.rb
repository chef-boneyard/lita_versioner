require "lita"
require "json"
require "uri"
require "fileutils"
require_relative "../../lita_versioner/build_in_progress_detector"
require_relative "../../lita_versioner/dependency_update_builder"
require_relative "../../lita_versioner/project_repo"
require_relative "bumpbot_handler"

module Lita
  module Handlers
    class DependencyUpdater < BumpbotHandler

      #
      # Command: update dependencies PROJECT
      #
      command_route(
        "update dependencies",
        "Runs the dependency updater and submits a build if there are new dependencies."
      ) do
        info("Checking for updated dependencies for #{project_name}...")
        update_dependencies
      end

      #
      # Command: reset dependency updates PROJECT
      #
      command_route(
        "reset dependency updates",
        "Forget failed dependency update builds (fixes 'waiting for the quiet period to expire before building again')."
      ) do
        project_repo.delete_branch(DEPENDENCY_BRANCH_NAME)
        output.inform("Deleted local branch #{DEPENDENCY_BRANCH_NAME} of #{project_name}.")
      end

      #
      # Event: load dependency updater and set up polling on start
      #
      on :loaded, :setup_polling

      #
      # Event: autobump (update dependencies on timer)
      #
      def update_dependencies_from_timer(proj_name)
        self.project_name = proj_name
        handle "autobump timer for #{proj_name}" do
          debug("Running scheduled dependency update for #{project_name}")
          update_dependencies
        end
      end

      #
      # Helpers (private)
      #

      DEPENDENCY_BRANCH_NAME = "auto_dependency_bump_test".freeze

      FAILURE_NOTIFICATION_RATE_LIMIT_FILE = "./cache/failure_notification_rate_limit".freeze
      FAILURE_NOTIFICATION_QUIET_TIME = 3600

      def setup_polling(args)
        handle "DependencyUpdater initial load" do
          unless config.polling_interval
            debug("Polling is disabled. Dependency updates will run from chat command only")
            return false
          end

          timer_fired = proc do |timer|
            projects.keys.each do |project|
              handler = DependencyUpdater.new(robot)
              handler.update_dependencies_from_timer(project)
            end
          end
        end

        every(config.polling_interval, &timer_fired)
      end

      def update_dependencies
        conflict_checker = BuildInProgressDetector.new(trigger: "#{project_name}-trigger-ad_hoc",
                                                       pipeline: project_name,
                                                       jenkins_username: config.jenkins_username,
                                                       jenkins_api_token: config.jenkins_api_token,
                                                       jenkins_endpoint: config.jenkins_endpoint,
                                                       target_git_ref: DEPENDENCY_BRANCH_NAME)
        if conflict_checker.conflicting_build_running?
          warn("Dependency update build not triggered: conflicting build in progress.")
          return false
        end

        dep_builder = DependencyUpdateBuilder.new(handler: self,
                                                  dependency_branch: DEPENDENCY_BRANCH_NAME)

        dependencies_updated, reason = dep_builder.run
        rate_limited_error!("Dependency update build not triggered: #{reason}") unless dependencies_updated

        success = trigger_build("#{project_name}-trigger-ad_hoc", DEPENDENCY_BRANCH_NAME)
        msg = "Started dependency update build for project #{project_name}.\n" +
          "Diff: https://github.com/chef/#{project_name}/compare/auto_dependency_bump_test"
        output.inform(msg)
        true
      end

      def failure_notification_rate_limit_file
        File.join(sandbox_directory, "failure_notification_rate_limit")
      end

      def rate_limit_exceeded?
        # Check if we've exceeded the rate limit
        if File.exist?(failure_notification_rate_limit_file)
          now = Time.new
          last_notification = File.mtime(failure_notification_rate_limit_file)
          elapsed = now - last_notification
          exceeded = elapsed < FAILURE_NOTIFICATION_QUIET_TIME

          if exceeded
            msg = "Last error #{elapsed.to_i}s ago, quiet period is #{FAILURE_NOTIFICATION_QUIET_TIME}s, suppressing notification."
            debug(msg)
          end
        end

        # Set the last notification time in the file
        parent_dir = File.dirname(failure_notification_rate_limit_file)
        FileUtils.mkdir_p(parent_dir) unless File.exist?(parent_dir)
        FileUtils.touch(failure_notification_rate_limit_file)

        # Return whether we exceeded or not
        exceeded
      end

      def rate_limited_error!(message)
        if rate_limit_exceeded?
          debug(message)
          raise ErrorAlreadyReported.new(message)
        else
          error!(message)
        end
      end

      Lita.register_handler(self)
    end
  end
end
