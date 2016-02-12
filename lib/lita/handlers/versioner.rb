require 'json'

module Lita
  module Handlers
    class Versioner < Handler
      http.post "/github_handler", :github_handler

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
