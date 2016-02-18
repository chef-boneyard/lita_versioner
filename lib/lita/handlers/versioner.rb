require "json"
require "uri"

module Lita
  module Handlers
    class Versioner < Handler
      config :jenkins_username, required: true
      config :jenkins_api_token, required: true

      http.post "/github_handler", :github_handler
      route(/^build/, :build, command: true, help: {
        "build PIPELINE <TAG>" => "Kicks off a build for PIPELINE with TAG. TAG default: master"
      })

      PROJECTS = {
        harmony: {
          pipeline: "harmony-trigger-ad_hoc",
          repository: "lita-test" # For testing purposes we are watching this repository.
        }
        # chef: {
        #   pipeline: "chef-trigger-release",
        #   repository: "chef"
        # }
      }

      def build(response)
        params = response.args
        unless params.length == 1 || params.length == 2
          response.reply("Argument issue. You can run this command like 'build PROJECT <TAG>'.")
          return
        end

        project = params.shift.to_sym
        build_tag = params.shift || "master"

        if PROJECTS[project].nil?
          response.reply("Project '#{project}' is not supported yet!")
          return
        end

        trigger_build(PROJECTS[project][:pipeline], build_tag)
      end

      def github_handler(request, response)
        payload = JSON.parse(request.params["payload"])

        event_type = request.env["HTTP_X_GITHUB_EVENT"]
        require 'pry'; binding.pry
        repository = payload["repository"]["name"]
        log "Processing '#{event_type}' event for '#{repository}'."

        # TODO make a struct that holds these objects, make PROJECTS just an array
        target_pipeline = nil
        target_project = nil
        PROJECTS.each do |project, project_data|
          if project_data[:repository] == repository
            log "Found matching project '#{project}'"
            target_pipeline = project_data[:pipeline]
            target_project = project
            break
          end
        end

        if target_pipeline.nil?
          log "Repository '#{repository}' is not monitored!"
          return
        end

        case event_type
        when "pull_request"
          # https://developer.github.com/v3/activity/events/types/#pullrequestevent
          # If the pull request is merged with some commits
          if payload["action"] == "closed" && payload["pull_request"]["merged"]
            log "Pull request '#{payload["pull_request"]["url"]}' is merged."
            # TODO: Update the version, tag and commit.
            # TODO: Kick off build using the tag we created
            trigger_build(target_pipeline, "master")
          else
            log "Skipping..."
          end
        else
          log "Skipping..."
        end
      end

      def clone_or_refresh(project, repository)
        wd = "/tmp/lita_versioner"
        Dir.mkdir_p wd
        if Dir.exists?(File.join(wd, repository))
          # git reset
          shellout = Mixlib::ShellOut.new("git reset --hard origin/master && git clean -fdx", cwd: File.join(wd, repository), timeout: 3600)
        else
          # git clone
          shellout = Mixlib::ShellOut.new("git clone #{repository} #{project}", cwd: wd, timeout: 3600)
        end
        shellout.run
        if shellout.error?
          log "Error running git command #{shellout.command}"
          log shellout.error
          return
        end
      end

      def trigger_build(pipeline, tag)
        log "Kicking off a build for #{pipeline} with #{tag}."

        status = rest_post("/job/#{pipeline}/buildWithParameters",
          "GIT_REF" => tag,
          "EXPIRE_CACHE" => false
        )

        begin
          # Raise if response is not 2XX
          status.value
        rescue Net::HTTPServerException => e
          log "Sorry, received HTTP error #{e.response.code} when kicking off the build!"
          log status.body
          return
        end

        log "Done!"
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

      def log(message)
        Lita.logger.info(message)
      end

      Lita.register_handler(self)
    end
  end
end
