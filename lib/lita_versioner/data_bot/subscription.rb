require_relative "data"

module LitaVersioner
  module DataBot
    #
    # Represents a subscription to events.
    #
    # Data objects fire events with `send_event`, and subscriptions can target
    # various data objects.
    #
    class Subscription < Data
      #
      # The data bot this subscription is a child of.
      #
      # @return [Bot] The data bot this subscription is in.
      #
      attr_reader :bot

      #
      # The channel or user that will receive the Slack messages.
      #
      # @return [Bot] The channel or user that will receive the Slack messages.
      #
      attr_reader :target

      #
      # The event filter to attach to.
      #
      # @return [Hash] The event filter.
      #
      attr_reader :filter

      #
      # Subscription options (such as "one_per_build").
      #
      # @return [Hash] The subscription options.
      #
      attr_reader :options

      def initialize(bot, target, filter, options)
        @bot = bot
        @target = target
        @filter = filter
        @options = options
      end

      #
      # Tell whether the given event properties match the filter.
      #
      # @param properties [Hash] The properties to match against.
      #
      # @return [Boolean] Whether the properties match the filter.
      #
      def properties_match?(properties)
        filter.each do |name, filter_value|
          # The event must have the property, and it must be equal
          return false unless properties[name]
          next if properties[name] == "*"
          return false unless properties[name] == filter_value
        end
        true
      end

      #
      # Called when this subscription is removed from the bot.
      #
      def removed
        messages = self.messages
        messages.each { |message| message.set_invisible(true) }
        @bot = nil
        @messages = nil
      end

      #
      # Send a Slack message to the target.
      #
      # @param slack_message [String] The Slack message.
      # @param create_message [Boolean] Whether to return a Message object (used
      #   by Message to avoid recursion--messages sent for Message events cannot
      #   be listened to).
      #
      # @return [Message] The resulting updateable message.
      #
      def send(message, create_message: true)
        bot.send_slack_message(target, message, create_message: create_message)
      end

      def slack_message
        "#{target} is subscribed to #{filter} with options #{options}"
      end

      def send_event(event)
        super(event, "subscription")
      end
    end
  end
end
