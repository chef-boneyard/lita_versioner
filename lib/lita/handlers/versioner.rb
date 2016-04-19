require "json"
require "uri"
require "lita/project_repo"

module Lita
  module Handlers
    class Versioner < Handler
      attr_reader :project
      attr_reader :inform_channel

      # NOTE: this configuration is shared with other handlers that have
      # `namespace "versioner"`. Check other handlers before changing or
      # removing any config settings here.

      config :jenkins_username, required: true
      config :jenkins_api_token, required: true
      config :polling_interval, default: false
      config :trigger_real_builds, default: false
      config :default_inform_channel, default: "engineering-services"

      http.post "/github_handler", :github_handler
      route(/^build/, :build, command: true, help: {
        "build PIPELINE <TAG>" => "Kicks off a build for PIPELINE with TAG. TAG default: master"
      })
      route(/^git_test/, :git_test, command: true)

      PROJECTS = {
        harmony: {
          pipeline: "harmony-trigger-ad_hoc",
          github_url: "git@github.com:chef/lita-test.git",
          version_bump_command: "bundle install && bundle exec rake version:bump_patch",
          version_show_command: "bundle exec rake version:show",
          inform_channel: "engineering-services"
        },
        chef: {
          pipeline: "chef-trigger-release",
          github_url: "git@github.com:chef/chef.git",
          version_bump_command: "bundle install && bundle exec rake version:bump && git checkout .bundle/config",
          version_show_command: "bundle exec rake version:show",
          inform_channel: "workflow-pool"
        },
        chefdk: {
          pipeline: "chefdk-trigger-release",
          github_url: "git@github.com:chef/chef-dk.git",
          version_bump_command: "bundle install && bundle exec rake version:bump && git checkout .bundle/config",
          version_show_command: "bundle exec rake version:show",
          inform_channel: "workflow-pool"
        }
      }

      def build(response)
        reset_state

        params = response.args
        unless params.length == 1 || params.length == 2
          response.reply("Argument issue. You can run this command like 'build PROJECT <TAG>'.")
          return
        end

        project_name = params.shift.to_sym
        build_tag = params.shift || "master"

        @project = PROJECTS[project_name]
        if project.nil?
          response.reply("Project '#{project_name}' is not supported yet!")
          return
        end

        trigger_build(build_tag)
      end

      def git_test(response)
        reset_state

        params = response.args
        unless params.length == 1
          response.reply("Argument issue. You can run this command like 'build PROJECT'.")
          return
        end

        project_name = params.shift.to_sym

        @project = PROJECTS[project_name]
        if project.nil?
          response.reply("Project '#{project_name}' is not supported yet!")
          return
        end

        new_version = bump_version_in_git
        response.reply("Bumped version of '#{project_name}' to #{new_version}")
      end

      def github_handler(request, response)
        reset_state

        payload = JSON.parse(request.params["payload"])

        event_type = request.env["HTTP_X_GITHUB_EVENT"]
        repository = payload["repository"]["full_name"]
        log "Processing '#{event_type}' event for '#{repository}'."

        PROJECTS.each do |project, project_data|
          if project_data[:github_url].match(/.*(\/|:)#{repository}.git/)
            @project = project_data
            break
          end
        end

        if project.nil?
          inform("Repository '#{repository}' is not monitored by versioner!")
          return
        end

        case event_type
        when "pull_request"
          # https://developer.github.com/v3/activity/events/types/#pullrequestevent
          # If the pull request is merged with some commits
          if payload["action"] == "closed"
            if payload["pull_request"]["merged"]
              inform("'#{payload["pull_request"]["html_url"]}' is just merged. Working on it...")
              new_version = bump_version_in_git
              trigger_build("v#{new_version}")
            else
              inform("Skipping: '#{payload["pull_request"]["html_url"]}'. It was closed without merging any commits.")
            end
          else
            log("Skipping: '#{payload["pull_request"]["html_url"]}' Action: '#{payload["action"]}' Merged? '#{payload["pull_request"]["merged"]}'")
          end
        else
          inform("Skipping event '#{event_type}' for '#{repository}'. I am only handling 'pull_request' events.")
        end
      end

      def bump_version_in_git
        project_repo = ProjectRepo.new(project)
        begin
          project_repo.refresh
          project_repo.bump_version
          project_repo.tag_and_commit
        rescue Lita::ProjectRepo::CommandError => e
          inform(e.to_s)
          raise
        end

        # we return the version we bumped to
        project_repo.read_version
      end

      def trigger_build(tag)
        pipeline = project[:pipeline]
        log "Kicking off a build for #{pipeline} with #{tag}."

        status = rest_post("/job/#{pipeline}/buildWithParameters",
          "GIT_REF" => tag,
          "EXPIRE_CACHE" => false
        )

        begin
          # Raise if response is not 2XX
          status.value
        rescue Net::HTTPServerException => e
          inform("Sorry, received HTTP error #{e.response.code} when kicking off the build!")
          inform(status.body)
          return
        end

        inform("Kicked off a build for '#{pipeline}' with tag '#{tag}'.")
      end

      JENKINS_ENDPOINT = "http://manhattan.ci.chef.co/".freeze
      def rest_post(path, parameters)
        uri = URI.parse(JENKINS_ENDPOINT)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")

        full_path = [path, URI.encode_www_form(parameters)].join("?")
        request = Net::HTTP::Post.new(full_path)
        request.basic_auth(config.jenkins_username, config.jenkins_api_token)
        request["Accept"] = "application/json"

        http.request(request)
      end

      def inform(message)
        if inform_channel.nil?
          inform_channel_name = project.nil? ? config.default_inform_channel : project[:inform_channel]
          inform_room = Lita::Room.fuzzy_find(inform_channel_name)
          @inform_channel = Source.new(room: inform_room)
        end

        log("Informing '#{inform_channel_name}' with: '#{message}'")
        robot.send_message(inform_channel, message)
      end

      def log(message)
        Lita.logger.info(message)
      end

      def reset_state
        @project = nil
        @inform_channel = nil
      end

      Lita.register_handler(self)
    end
  end
end
