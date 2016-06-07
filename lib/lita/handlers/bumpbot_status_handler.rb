require_relative "bumpbot_handler"
require_relative "../../lita_versioner/format_helpers"

module Lita
  module Handlers
    class BumpbotStatusHandler < BumpbotHandler
      include LitaVersioner::FormatHelpers

      #
      # Command: bumpbot running handlers
      #
      command_route(
        "bumpbot running handlers",
        "Get the list of running handlers in bumpbot",
        project_arg: false
      ) do
        running_handlers = self.running_handlers.reject { |handler| handler == self }
        if running_handlers.any?
          running_handlers.sort_by { |handler| [ handler.start_time, handler.handler_id.to_i ] }.reverse_each do |handler|
            info("#{handler.title} running since #{how_long_ago(handler.start_time)}. <#{config.lita_url}/bumpbot/handlers/#{handler.handler_id}/handler.log|Log> <#{config.lita_url}/bumpbot/handlers/#{handler.handler_id}/sandbox.tgz|Download Sandbox>")
          end
        else
          info("No command or event handlers are running right now.")
        end
      end

      #
      # Command: bumpbot handlers
      #
      command_route(
        "bumpbot handlers",
        { "[RANGE]" => "Get the list of running and failed handlers in bumpbot (corresponds to the list of failed commands). Optional RANGE will get you a list of handlers. Default range is 1-10." },
        project_arg: false,
        max_args: 1
      ) do |range = "1-10"|
        raise "Range must be <start index>-<end index>!" unless range =~ /^(\d+)(-)?(\d*)$/
        raise "Range start cannot be 0 (starts at 1!)" if $1 == "0"

        handlers = list_handlers
        handlers.reject! { |handler_id, handler, title, start_time, end_time, failed| handler == self }

        if $2 == "-"
          if $3 == ""
            range = $1.to_i..handlers.size
          else
            range = $1.to_i..$3.to_i
          end
        else
          range = $1.to_i..$1.to_i
        end
        range = Range.new(range.min, handlers.size) if range.max > handlers.size
        range = Range.new(handlers.size, range.max) if range.min && range.min > handlers.size

        if handlers.any?
          handlers.each_with_index do |(handler_id, handler, title, start_time, end_time, failed), index|
            next unless range.include?(index + 1)
            if end_time
              if failed
                status = "failed #{how_long_ago(start_time)} after #{format_duration(end_time - start_time)}"
              else
                status = "succeeded #{how_long_ago(start_time)} after #{format_duration(end_time - start_time)}"
              end
            else
              status = "running since #{how_long_ago(start_time)}"
            end
            info("#{title} #{status}. <#{config.lita_url}/bumpbot/handlers/#{handler_id}/handler.log|Log> <#{config.lita_url}/bumpbot/handlers/#{handler_id}/sandbox.tgz|Download Sandbox>")
          end
          if handlers.size > range.max
            info("This is only handlers #{range.min}-#{range.max} out of #{handlers.size}. To show the next 10, say \"handlers #{range.max + 1}-#{range.max + 11}\".")
          end
        else
          info("The system is not running any handlers, and nothing has failed, so there is no handler history to show.")
        end
      end

      #
      # Helpers (private)
      #

      def list_handlers
        handlers = {}
        redis.scan_each(match: "handlers:*") do |key|
          handler_id = key.split(":", 2)[1]
          title, start_time, end_time, failed = redis.hmget("handlers:#{handler_id}", "title", "start_time", "end_time", "failed")
          next unless title
          start_time = Time.at(start_time.to_i).utc if start_time
          end_time = Time.at(end_time.to_i).utc if end_time
          handler = running_handlers.find { |h| h.handler_id.to_i == handler_id.to_i }
          handlers[handler_id] = [ handler, title, start_time, end_time, failed ]
        end

        # Sort in reverse
        handlers = handlers.map { |handler_id, data| [ handler_id, *data ] }
        handlers.sort_by! { |handler_id, *data| handler_id.to_i }
        handlers.reverse!

        handlers
      end

      Lita.register_handler(self)
    end
  end
end
