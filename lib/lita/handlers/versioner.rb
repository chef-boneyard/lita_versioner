require 'json'

module Lita
  module Handlers
    class Versioner < Handler
      config :jenkins_username, required: true
      config :jenkins_api_token, required: true

      http.post "/github_handler", :github_handler
      route(/^build\s+(.+)/, :build, command: true, help: {
        "build PIPELINE <TAG>" => "Kicks off a build for PIPELINE with TAG. TAG default: master"
      })

      def build(response)
        params = response.args
        unless params.length == 1 || params.length == 2
          log "Argument issue. You can run this command like 'build PIPELINE <TAG>'"
          return
        end

        pipeline_name = params.shift
        build_tag = params.shift || "master"
        log "Kicking off a build for #{pipeline_name} with #{build_tag}."

        status = rest_post(
          "GIT_REF" => build_tag,
          "EXPIRE_CACHE" => false
        )

        if status
          response.reply "Done!"
        else
          response.reply "Sorry, there was an error when kicking off the build!"
        end
      end

      ENDPOINT = "http://manhattan.ci.chef.co/".freeze

      def rest_post(parameters)
        uri = URI.parse(ENDPOINT)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")

        path = "/job/harmony-trigger-ad_hoc/buildWithParameters"
        full_path = [path, URI.encode_www_form(parameters)].join("?")
        request = Net::HTTP::Post.new(full_path)
        request.basic_auth(config.jenkins_username, config.jenkins_api_token)
        request["Accept"] = "application/json"

        res = http.request(request)

        begin
          # Raise if response is not 2XX
          res.value
        rescue
          return false
        end

        true
      end


      def github_handler(request, response)
        payload = JSON.parse(request.params["payload"])

        event_type = request.env['HTTP_X_GITHUB_EVENT']
        log "Processing '#{event_type}' event for '#{payload["repository"]["name"]}'."

        case event_type
        # https://developer.github.com/v3/activity/events/types/#pullrequestevent
        when "pull_request"
          # If the pull request is merged with some commits
          if payload["action"] == "closed" && payload["pull_request"]["merged"]
            log "Pull request '#{payload["pull_request"]["url"]}' is merged."
          else
            log "Skipping"
          end
        else
          log "Skipping..."
        end
      end

      def log(message)
        Lita.logger.info(message)
      end

      Lita.register_handler(self)
    end
  end
end
