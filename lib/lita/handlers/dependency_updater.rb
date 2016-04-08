require "json"
require "uri"
require "lita/build_in_progress_detector"
require "lita/dependency_update_builder"
require "lita/project_repo"
require "lita/jenkins_http"

module Lita
  module Handlers
    class DependencyUpdater < Handler

      DEPENDENCY_BRANCH_NAME = "auto_dependency_bump_test".freeze
      JENKINS_ENDPOINT = "http://manhattan.ci.chef.co/".freeze

      attr_reader :project
      attr_reader :inform_channel

      config :jenkins_username, required: true
      config :jenkins_api_token, required: true
      config :default_inform_channel, default: "engineering-services"

      #on :loaded, :setup_polling

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
          version_bump_command: "bundle install && bundle exec rake version:bump",
          version_show_command: "bundle exec rake version:show",
          dependency_update_command: "bundle install && bundle exec rake dependencies",
          inform_channel: "ship-it"
        }
      }

      def update_dependencies_from_command(response)
        project_name = response.args.first
        # if project_name.nil? then reply w/ help (?)
        # unless PROJECTS.has_key?(project_name.to_sym) then reploy w/ err, list of known projects
        build_triggered, reason = update_dependencies(project_name)

        if build_triggered
          response.reply("Started build with updated dependencies.")
        else
          response.reply("Build not triggered: #{reason}")
        end
      end

      def forget_bump_deps_builds(response)
        project_name = response.args.first
        # if project_name.nil? then reply w/ help (?)
        # unless PROJECTS.has_key?(project_name.to_sym) then reploy w/ err, list of known projects
        project_info = PROJECTS[project_name.to_sym]

        repo = ProjectRepo.new(project_info)
        repo.refresh
        repo.delete_branch(DEPENDENCY_BRANCH_NAME)
      end

      def setup_polling
        every(600) do |timer|

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
          # TODO: re-enable (should be configurable?)
          Lita.logger.info("Would have triggered a build")
          #trigger_jenkins_job(pipeline_name)
          [true, "build started"]
        else
          [false, reason]
        end
      end

      def trigger_jenkins_job(pipeline)
        jenkins = JenkinsHTTP.new(base_uri: JENKINS_ENDPOINT,
                                  username: config.jenkins_username,
                                  api_token: config.jenkins_api_token)
        # notify channel of jenkins job
        jenkins.post("/job/#{pipeline}-trigger-ad_hoc/buildWithParameters",
                     "GIT_REF" => DEPENDENCY_BRANCH_NAME,
                     "EXPIRE_CACHE" => false)
      end


      Lita.register_handler(self)
    end
  end
end

