module LitaVersioner
  class SlackAPI
    class Message
      attr_reader :bot
      attr_reader :channel
      attr_reader :ts

      def initialize(bot, channel, ts)
        @bot = bot
        @channel = channel
        @ts = ts
      end

      def send_event(event, subject, event_properties={})
        event_properties["channel"] = channel
        event_properties["ts"] = ts
      end

      def update(message)
        bot.slack_api.post("chat.update", channel: channel, ts: ts, message: message)
      end

      def delete
        bot.slack_api.post("chat.delete", channel: channel, ts: ts)
      end
    end
    end
  end
end
