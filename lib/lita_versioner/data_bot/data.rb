require "json"
require_relative "../format_helpers"

module LitaVersioner
  module DataBot
    #
    # Base class for Data. Can be loaded or saved. Can fire events.
    #
    class Data
      include FormatHelpers

      #
      # The bot this data is a part of.
      #
      # @return [Bot] The bot this data is a part of.
      #
      def bot
        raise "#{self.class}.bot must be implemented!"
      end

      #
      # The data in this class. Will be loaded from redis if not there.
      #
      # @return [Hash] The data in the class.
      #
      def data
        @data || load_data
      end

      #
      # Send an event to matching subscriptions.
      #
      # `slack_message(subscription, event_properties)` will be called on each
      # matching subscription.
      #
      # @param event [String] The event name, e.g. `"added"` or `"updated"`.
      # @param subject [String] The subject of the event, e.g. `"project"` or `"subscription"`.
      # @param event_properties [Hash] A hash of event properties to match against
      #   the event.
      #
      def send_event(event, subject, event_properties={})
        debug "Sending event #{event} #{subject} (#{event_properties})"
        bot.subscriptions(event, subject, event_properties).each do |subscription|
          if block_given?
            yield subscription, event, subject, event_properties
          else
            subscription.send(slack_message)
          end
        end
      end

      #
      # Generate a Slack message for this object.
      #
      # Must be overridden unless you override `send_event`.
      #
      # @return [String,Hash] The Slack message to send.
      #
      def slack_message
        raise "Must override slack_message!"
      end

      #
      # Get the handler.
      #
      # @return [Handler] The current handler.
      #
      def handler
        Thread.local_variable_get(:handler) || raise "Handler not set! You must use Bot.with(handler) to use the bot."
      end

      extend Forwardable
      def_delegators :handler, :error, :warn, :info, :debug, :log_task, handler_log_url

      protected

      #
      # The path to this data in redis.
      #
      def redis_path
        nil
      end

      #
      # Load data from redis.
      #
      def load_data
        if redis_path
          @data = JSON.parse(handler.redis.get(redis_path)
        end
        @data ||= {}
      end

      #
      # Set the data, saving it to redis.
      #
      def save_data(data)
        @data = data
        handler.redis.set(redis_path, data) if redis_path
      end
    end
  end
end
