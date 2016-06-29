# Extracted from lita-slack plugin

require_relative "slack_api/message"

module LitaVersioner
  class SlackAPI
    attr_reader :log
    attr_reader :config

    def initialize(log, config)
      @log = log
      @config = config
    end

    def connection
      Faraday.new
    end

    def message(log, channel, ts)
      Message.new(log, channel, ts)
    end

    #
    # Call the Slack API method with the given arguments
    #
    # @param method [String] The Slack API method. e.g. `"chat.postMessage"`.
    #   The full URL posted to will be https://slack.com/api/chat.postMessage.
    # @param arguments [Hash] A Hash of arguments to pass to the Slack API.
    #   Array and Hash values will be converted to JSON. `token`
    #   will be passed automatically.
    #
    # @return [Hash] The parsed response, typically `{ "ok" => true, ... }`
    # @raise [RuntimeError] If the server returns a non-200 or returns
    #   `{ "ok" => false }`.
    #
    def post(method, **arguments)
      arguments.each do |key, value|
        arguments[key] =
          case value
          when Lita::Source
            if value.private_message?
              im = post("im.open", user: value.user.id)
              im["channel"]["id"]
            else
              value.room
            end

          when Lita::Room, Lita::User
            target.id

          # Array and Hash arguments must be JSON-encoded
          when Enumerable
            JSON.dump(value)

          else
            value
          end
      end

      log.info("POST https://slack.com/api/#{method}")
      debug("    Arguments: #{arguments}")
      response = connection.post(
        "https://slack.com/api/#{method}",
        token: config.adapters.slack.token,
        **arguments
      )

      unless response.success?
        log.error("Bad HTTP status code from POST https://slack.com/api/#{method}: #{response.status}")
        raise "Slack API call to #{method} failed with status code #{response.status}: '#{response.body}'. Headers: #{response.headers}. Arguments: #{arguments}"
      end

      data = JSON.parse(response.body)

      if data["error"]
        log.error("Slack error from POST https://slack.com/api/#{method}: #{data["error"]}")
        raise "Slack API call to #{method} returned an error: #{data["error"]}. Arguments: #{arguments}"
      end

      log.info("Success from POST https://slack.com/api/#{method}: #{response.status}.")
      debug("     Data: #{data}")
      data
    end
  end
end
