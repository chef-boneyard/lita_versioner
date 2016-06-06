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
            info("#{handler.title} started #{how_long_ago(handler.start_time)}. <#{config.lita_url}/bumpbot/handlers/#{handler.handler_id}/log|Log> <#{config.lita_url}/bumpbot/handlers/#{handler.handler_id}/download_sandbox|Download Sandbox>")
          end
        else
          info("No command or event handlers are running right now.")
        end
      end

      #
      # Command: bumpbot sandboxes
      #
      command_route(
        "bumpbot handlers",
        { "[RANGE]" => "Get the list of running and failed handlers in bumpbot (corresponds to the list of failed commands). Optional RANGE will get you a list of sandboxes. Default range is 1-10." },
        project_arg: false,
        max_args: 1
      ) do |range="1-10"|
        raise "Range must be <start index>-<end index>!" unless range =~ /^(\d+)(-)?(\d*)$/
        raise "Range start cannot be 0 (starts at 1!)" if $1 == "0"

        sandboxes = read_sandboxes
        sandboxes.reject! { |handler_id, handler, title, end_time| handler == self }

        if $2 == "-"
          if $3 == ""
            range = $1.to_i..sandboxes.size
          else
            range = $1.to_i..$3.to_i
          end
        else
          range = $1.to_i..$1.to_i
        end

        if sandboxes.any?
          sandboxes.each_with_index do |(handler_id, handler, title, end_time), index|
            next unless range.include?(index+1)
            if handler
              status = "started #{how_long_ago(handler.start_time)}"
            else
              status = "failed #{how_long_ago(end_time)}"
            end
            info("#{title} #{status}. <#{config.lita_url}/bumpbot/handlers/#{handler_id}/log|Log> <#{config.lita_url}/bumpbot/handlers/#{handler_id}/download_sandbox|Download Sandbox>")
          end
          if sandboxes.size > range.max
            info("This is only handlers #{range.min}-#{range.max} out of #{sandboxes.size}. To show the next 10, say \"handlers #{range.max+1}-#{range.max+11}\".")
          end
        else
          info("The system is not running any handlers, and nothing has failed, so there is no handler history to show.")
        end
      end

      #
      # Helpers (private)
      #

      def read_sandboxes
        if File.directory?(config.sandbox_directory)
          # Get all sandbox directories
          sandboxes = Dir.entries(config.sandbox_directory).select do |entry|
            File.directory?(File.join(config.sandbox_directory, entry)) && entry =~ /^\d+$/
          end
        else
          sandboxes = []
        end

        # Get handler, title and end time
        sandboxes.map! do |handler_id|
          handler = running_handlers.find { |handler| handler.handler_id == handler_id }
          if handler
            title = handler.title
            end_time = Time.now.utc
          else
            # This is not currently running. Get status from disk
            # end time is mtime of the logfile
            title_filename = File.join(config.sandbox_directory, handler_id, "title.txt")
            begin
              end_time = File.mtime(title_filename).utc
              title = IO.read(title_filename).chomp
            rescue Errno::ENOENT
              next
            end
          end
          [ handler_id, handler, title, end_time ]
        end

        # Add stuff which doesn't have a sandbox yet
        running_handlers.each do |running_handler|
          unless sandboxes.any? { |id,handler,title,end_time| handler == running_handler }
            sandboxes << [ running_handler.handler_id.to_i, running_handler, running_handler.title, Time.now.utc ]
          end
        end

        # Sort in reverse
        sandboxes.sort_by! { |handler_id, handler, title, end_time| [ end_time, handler_id.to_i ] }
        sandboxes.reverse!

        sandboxes
      end

      Lita.register_handler(self)
    end
  end
end
