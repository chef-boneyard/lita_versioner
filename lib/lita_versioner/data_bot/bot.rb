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
        slack_api.post("chat.postMessage", channel: target, link_names: 1, parse: "none", message: message)
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

            # Put together the Slack message for each result
            attachments = []
            Array(results).each do |result|
              message = result.slack_message
              next unless message
              raise "Message #{message} must only have attachments!" if (message.keys - [ :attachments ]).any?
              if message[:attachments]
                attachments += message[:attachments]
              end
            end

            # Send the Slack response
            handler.respond(attachments: attachments) if attachments.any?
          end
        end
      end

      #
      # Parses the command string.
      #
      def self.parse_command()

      #
      # Define a chat route with the given command name and arguments.
      #
      # A bumpbot chat command generally looks like @julia command project *args
      #
      # @param command [String] name of the command, e.g. 'build'.
      # @param method_sym [Symbol] method to dispatch to.  No arguments are passed.
      # @param help [Hash : String -> String] usage help strings, e.g.
      #   {
      #     'EXTRA_ARG_NAME' => 'some usage',
      #     'DIFFERENT_ARG SEQUENCE HERE' => 'different usage'
      #   }
      # @param project_arg [Boolean] Whether the first arg should be PROJECT or not. Default: true
      # @param max_args [Int] Maximum number of extra arguments that this command takes.
      #
      def self.command_route(command, help, project_arg: true, max_args: 0, &block)
        help = { "" => help } unless help.is_a?(Hash)

        complete_help = {}
        help.each do |arg, text|
          if project_arg
            complete_help["#{command} PROJECT #{arg}".strip] = text
          else
            complete_help["#{command} #{arg}".strip] = text
          end
        end
        route(/^#{command}(\s|$)/, nil, command: true, help: complete_help) do |response|
          handle_command(command, response, help: complete_help, project_arg: project_arg, max_args: max_args, &block)
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
