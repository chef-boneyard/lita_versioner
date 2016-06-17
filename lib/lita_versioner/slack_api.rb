# Extracted from lita-slack plugin

module LitaVersioner
  class SlackAPI
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def connection
      Faraday.new
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

      response = connection.post(
        "https://slack.com/api/#{method}",
        token: config.adapters.slack.token,
        **arguments
      )

      unless response.success?
        raise "Slack API call to #{method} failed with status code #{response.status}: '#{response.body}'. Headers: #{response.headers}. Arguments: #{arguments}"
      end

      data = JSON.parse(response.body)

      if data["error"]
        raise "Slack API call to #{method} returned an error: #{data["error"]}. Arguments: #{arguments}"
      end

      data
    end
  end
end
