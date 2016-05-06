require "json"
require "uri"
require "fileutils"
require "lita/build_in_progress_detector"
require "lita/dependency_update_builder"
require "lita/project_repo"
require "lita/jenkins_http"

module Lita
  module Handlers
    class DependencyUpdater < Handler

      # Share the "versioner" configuration namespace with the Versioner
      # handler. This means that config settings are defined in the Versioner's
      # class definition and not in here.
      namespace "versioner"

      DEPENDENCY_BRANCH_NAME = "auto_dependency_bump_test".freeze
      JENKINS_ENDPOINT = "http://manhattan.ci.chef.co/".freeze

      FAILURE_NOTIFICATION_RATE_LIMIT_FILE = "./cache/failure_notification_rate_limit".freeze
      FAILURE_NOTIFICATION_QUIET_TIME = 3600

      attr_reader :project
      attr_reader :inform_channel

      on :loaded, :setup_polling

      route(/^bump\-deps/, :update_dependencies_from_command,
        command: true,
        help: { "bump-deps PROJECT" => "Runs the dependency bumper and submits a build if there are new deps" })

      route(/^forget-bump-deps-builds/, :forget_bump_deps_builds,
        command: true,
        help: { "forget-bump-deps-builds PROJECT" => "Forget failed bump-deps builds (fixes 'waiting for the quiet period to expire before building again')" })

      PROJECTS = {
        chefdk: {
          pipeline: "chefdk-trigger-release",
          github_url: "git@github.com:chef/chef-dk.git",
          version_bump_command: "bundle install && bundle exec rake version:bump && git checkout .bundle/config",
          version_show_command: "bundle exec rake version:show",
          dependency_update_command: "bundle install && bundle exec rake dependencies && git checkout .bundle/config",
          inform_channel: "workflow-pool",
        },
        chef: {
          pipeline: "chef-trigger-release",
          github_url: "git@github.com:chef/chef.git",
          version_bump_command: "bundle install && bundle exec rake version:bump && git checkout .bundle/config",
          version_show_command: "bundle exec rake version:show",
          dependency_update_command: "bundle install && bundle exec rake dependencies && git checkout .bundle/config",
          inform_channel: "workflow-pool",
        },
      }

      def update_dependencies_from_command(response)
        project_name = response.args.first
        response.reply("Checking for updated dependencies for #{project_name}...")

        unless project_name_valid?(project_name)
          response.reply("Invalid project name `#{project_name}'. Valid projects: '#{PROJECTS.keys.join("', '")}'")
          return false
        end

        build_triggered, reason = update_dependencies(project_name)

        if build_triggered
          response.reply("Started build with updated dependencies.")
        else
          response.reply("Build not triggered: #{reason}")
        end
      end

      def forget_bump_deps_builds(response)
        project_name = response.args.first

        unless project_name_valid?(project_name)
          response.reply("Invalid project name `#{project_name}'. Valid projects: '#{PROJECTS.keys.join("', '")}'")
          return false
        end

        project_info = PROJECTS[project_name.to_sym]

        repo = ProjectRepo.new(project_info)
        repo.refresh
        repo.delete_branch(DEPENDENCY_BRANCH_NAME)
        response.reply("Deleted local branch #{DEPENDENCY_BRANCH_NAME} of #{project_name}.")
      end

      def setup_polling(args)
        unless config.polling_interval
          Lita.logger.info "Polling is disabled. Dependency updates will run from chat command only"
          return false
        end
        every(config.polling_interval) do |timer|
          PROJECTS.keys.each do |project|
            Lita.logger.info("Running scheduled dependency update for #{project}")
            update_dependencies(project.to_s)
          end
        end
      end

      def update_dependencies(pipeline_name)
        project_info = PROJECTS[pipeline_name.to_sym]

        conflict_checker = BuildInProgressDetector.new(pipeline: pipeline_name,
                                                       jenkins_username: config.jenkins_username,
                                                       jenkins_api_token: config.jenkins_api_token)
        if conflict_checker.conflicting_build_running?
          Lita.logger.info("Conflicting build in progress, skipping dependency update")
          return [false, "Conflicting build in progress, skipping dependency update"]
        end

        dep_builder = DependencyUpdateBuilder.new(repo_url: project_info[:github_url],
                                                  dependency_branch: DEPENDENCY_BRANCH_NAME,
                                                  dependency_update_command: project_info[:dependency_update_command])

        dependencies_updated, reason = dep_builder.run
        if dependencies_updated
          trigger_jenkins_job(pipeline_name)
          msg = "Started dependency update build for project #{pipeline_name}. Diff: https://github.com/chef/#{pipeline_name}/compare/auto_dependency_bump_test"
          inform(msg, project_info)
          [true, "build started"]
        else
          [false, reason]
        end
      rescue => e
        Lita.logger.error(e)
        e.backtrace.each { |l| Lita.logger.error("  #{l}") }
        maybe_notify_about_error(e, pipeline_name, project_info)
        [ false, "#{e.class.name}:\n#{e.message}" ]
      end

      def trigger_jenkins_job(pipeline)
        unless config.trigger_real_builds
          Lita.logger.info("Would have triggered a build")
          return false
        end

        jenkins = JenkinsHTTP.new(base_uri: JENKINS_ENDPOINT,
                                  username: config.jenkins_username,
                                  api_token: config.jenkins_api_token)
        # notify channel of jenkins job
        jenkins.post("/job/#{pipeline}-trigger-ad_hoc/buildWithParameters",
                     "GIT_REF" => DEPENDENCY_BRANCH_NAME,
                     "EXPIRE_CACHE" => false)
      end

      def maybe_notify_about_error(e, project_name, project_info)
        if File.exist?(FAILURE_NOTIFICATION_RATE_LIMIT_FILE)
          now = Time.new
          last_notification = File.mtime(FAILURE_NOTIFICATION_RATE_LIMIT_FILE)
          elapsed = now - last_notification
          if elapsed < FAILURE_NOTIFICATION_QUIET_TIME
            msg = "Last error #{elapsed.to_i}s ago, quiet period is #{FAILURE_NOTIFICATION_QUIET_TIME}s, suppressing notification."
            Lita.logger.info(msg)
            return nil
          end
        end

        parent_dir = File.dirname(FAILURE_NOTIFICATION_RATE_LIMIT_FILE)
        FileUtils.mkdir_p(parent_dir) unless File.exist?(parent_dir)
        FileUtils.touch(FAILURE_NOTIFICATION_RATE_LIMIT_FILE)
        message = "Attempted dependency update for #{project_name} failed.\nError was #{e.class.name}:" +
          "\n```\n#{e}\n```"
        inform(message, project_info)
      end

      def inform(message, project_info)
        inform_channel_name = project_info[:inform_channel]

        if robot.config.robot.adapter == :shell
          Lita.logger.info("Would have informed channel #{inform_channel_name} with message: #{message}")
          return false
        end
        inform_room = Lita::Room.fuzzy_find(inform_channel_name)
        inform_channel = Source.new(room: inform_room)

        Lita.logger.info("Informing '#{inform_channel_name}' with: '#{message}'")
        robot.send_message(inform_channel, message)
        true
      end

      def project_name_valid?(project_name)
        return false if project_name.nil?
        return false unless PROJECTS.has_key?(project_name.to_sym)
        true
      end

      Lita.register_handler(self)
    end
  end
end
