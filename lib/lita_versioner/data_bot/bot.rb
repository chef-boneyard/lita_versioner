require_relative "../slack_api"
require_relative "data"
require_relative "subscription"

module LitaVersioner
  module DataBot
    #
    # A bot that helps you present updateable data as Slack messages and webpages.
    #
    # Keeps track of live messages, allowing you to update them.
    #
    class Bot < Data
      #
      # Perform an operation with the bot, from a Lita handler.
      #
      # Use a Thread-local variable to store the handler so we can log and perform
      # actions in its context during the `with` block. All bot operations must
      # take place in this context.
      #
      # @param handler [Lita::Handler] The Lita handler performing the operation.
      # @param block [Proc] The block to run.
      #
      # @return The return value of the block.
      #
      def self.with(handler, &block)
        old_handler = Thread.thread_variable_get(:handler)
        Thread.thread_variable_set(:handler, handler)
        begin
          @bot ||= self.class.new(handler.config)
          block.call(@bot)
        ensure
          Thread.thread_variable_set(:handler, old_handler)
        end
      end

      #
      # Get the emoji to use instead of a color when transforming a series of
      # attachments into a list.
      #
      # By default, "good" = `:white_check_mark:`, "warning" = `:grey_question`
      # and "danger" = `:x:`. Everything else is `:white_small_square` by default.
      #
      # @param color [String] The attachment color.
      #
      # @return [String] The emoji for the given color.
      #
      def list_emoji(color)
        emoji = (data["list_emoji"] && data["list_emoji"][color]
        emoji || begin
          case color
          when "good"
            ":white_check_mark:"
          when "warning"
            ":grey_question:"
          when "danger"
            ":x"
          else
            ":white_small_square:"
          end
        end
      end

      #
      # Bot configuration.
      #
      # @param [Lita::Config] The Lita config.
      #
      attr_reader :config

      #
      # Current subscriptions.
      #
      # @return [Array<Subscription>] Current subscriptions.
      #
      def subscriptions
        data["subscriptions"].map { |target, (filter, options)| Subscription.new(self, target, filter, options) }
      end

      #
      # Add or update the target's subscription.
      #
      # @param target [String] The channel (#channel) or user (@user) that will
      #   receive the Slack messages.
      # @param filter [Hash] The event filter.
      #
      # @return [Subscription] The subscription.
      #
      def subscribe(target, filter, options)
        # Subscriptions don't really have useful keys yet, so we just store them
        # in the bot's data for now.
        existed_already = data["subscriptions"].has_key?(target)
        data["subscriptions"][target] = [ filter, options ]
        save_data
        subscription = Subscription.new(self, target, filter, options)
        subscription.send_event(existed_already ? "updated" : "added")
        subscription
      end

      #
      # Remove an existing subscription.
      #
      # @param target [String] The subscribed channel (#channel) or user (@user).
      #
      # @return [Subscription] The deleted subscription (if any).
      def unsubscribe(target)
        filter, options = data["subscriptions"].delete(target)
        if filter
          Subscription.new(self, target, filter, options).send_event("removed")
        end
      end

      #
      # Slack messaging API helper.
      #
      # @return [SlackAPI] A Slack messaging API helper.
      #
      def slack_api
        if Lita.config.robot.adapter == :slack
          SlackAPI.new(self, Lita.config.robot)
        end
      end

      #
      # Send a Slack message.
      #
      # @param target [String] The channel or user to send to ("@user" or "#channel").
      # @param message [Hash] The message to send.
      #
      def send_slack_message(target, message)
        message = to_slack_message(message)
        if message
          slack_api.post("chat.postMessage",
            channel: target,
            link_names: 1,
            parse: "none",
            mrkdwn_in: %w{text pretext fields},
            **message)
          end
        end
      end

      #
      # Transforms the result of `slack_message` to arguments that can be sent to Slack.
      #
      # Strings are transformed into colorless attachments.
      #
      # Data will have `slack_message` called on them and then transformed.
      #
      # Arrays yield a single attachment in list form so that "more ..." will
      # work. Colors are transformed into emojis via `list_emoji`.
      #
      # Hashes are passed through verbatim.
      #
      # @param message [String,Hash,nil,Array,Data] The message to transform.
      # @return [Hash,nil] The resulting message.
      #
      def to_slack_message(message)
        case message
        when String
          {
            attachments: [{ text: slack_message }]
          }
        when Hash,nil
          message
        when Array
          # Transform array of text into a text list to allow "More..." to work.
          items = []
          message.each do |item|
            item = to_slack_message(item)
            next if item.nil?
            raise "Cannot turn #{item} into a list item: must have only attachments." if item.keys == [ :attachments ]
            item[:attachments].each do |attachment|
              raise "Cannot turn #{attachment} into a list item: must have only color and text keys" if (item.keys - [ :color, :text ]).any?
              items << "#{list_emoji(item[:color])} #{item[:text]}"
            end
          end
          return nil if items.empty?
          { attachments: [{ text: items.join("\n") }]}
        when Data
          to_slack_message(data.slack_message)
        else
          message
        end
      end

      #
      # Adds a command route for the given Lita command.
      #
      def self.command(command, &block)
        command_route(command) do |*args|
          # This gets run as a handler.
          with(self) do |bot|
            # Run the command and get results
            results = bot.instance_exec(*args, &block)

            message = to_slack_message(results.slack_message)

            # Send the Slack response
            if message
              handler.respond(
                link_names: 1,
                parse: "none",
                mrkdwn_in: %w{text pretext fields},
                **message
              )
            end
          end
        end
      end

      protected

      #
      # Create a new DataBot.
      #
      # @param [Lita::Config] Bot configuration.
      #
      def initialize(config)
        @config = config
      end
    end
  end
end
