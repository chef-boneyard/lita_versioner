require "json"
require "uri"
require "lita/build_in_progress_detector"
require "lita/dependency_update_builder"
require "lita/project_repo"

module Lita
  module Handlers
    class DependencyUpdater < Handler

      DEPENDENCY_BRANCH_NAME = "auto_dependency_bump_test".freeze

      attr_reader :project
      attr_reader :inform_channel

      config :jenkins_username, required: true
      config :jenkins_api_token, required: true
      config :default_inform_channel, default: "engineering-services"

      #on :loaded, :setup_polling

      route(/^bump\-deps/, :update_dependencies_from_command,
        command: true,
        help: { "bump-deps PROJECT" => "Runs the dependency bumper and submits a build if there are new deps" })

      PROJECTS = {
      ##   harmony: {
      ##     pipeline: "harmony-trigger-ad_hoc",
      ##     github_url: "git@github.com:chef/lita-test.git",
      ##     version_bump_command: "bundle install && bundle exec rake version:bump_patch",
      ##     version_show_command: "bundle exec rake version:show",
      ##     inform_channel: "engineering-services"
      ##   },
      ##   chef: {
      ##     pipeline: "chef-trigger-release",
      ##     github_url: "git@github.com:chef/chef.git",
      ##     version_bump_command: "bundle install && bundle exec rake version:bump",
      ##     version_show_command: "bundle exec rake version:show",
      ##     inform_channel: "ship-it"
      ##   },
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
        #update_dependencies_from_command
        update_dependencies(project_name)
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
          # reply if this was a slack command
          # early return
        end

        dep_builder = DependencyUpdateBuilder.new(repo_url: project_info[:github_url],
                                                  dependency_branch: DEPENDENCY_BRANCH_NAME,
                                                  dependency_update_command: project_info[:dependency_update_command])

        if dep_builder.run
          # trigger_jenkins_job
          # notify channel of jenkins job
          status = rest_post("/job/#{pipeline}/buildWithParameters",
            "GIT_REF" => tag,
            "EXPIRE_CACHE" => false
          )


        else
          # reply if this was a slack command
        end
      end


      Lita.register_handler(self)
    end
  end
end

