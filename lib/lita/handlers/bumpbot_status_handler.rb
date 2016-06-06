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
        running_handlers = self.running_handlers.dup
        if running_handlers.any?
          running_handlers.sort_by { |handler| handler.start_time }.reverse_each do |handler, title|
            info("#{handler.handler_id} #{title}: started #{how_long_ago(handler.start_time)}. <#{config.lita_url}/bumpbot/handlers/#{handler_id}/log|Log> <#{config.lita_url}/bumpbot/handlers/#{handler_id}/download_sandbox|Download Sandbox>")
          end
        else
          # Technically, this should never happen because we are a running handler, but eh
          error!("No running handlers!")
        end
      end

      #
      # Command: bumpbot sandboxes
      #
      command_route(
        "bumpbot sandboxes",
        { "[RANGE]" => "Get the list of sandboxes in bumpbot (corresponds to the list of failed commands). Optional RANGE will get you a list of sandboxes. Default range is 1-5. Starts at 1." },
        project_arg: false
      ) do |range="1-5"|
        raise "Range must be <start index>-<end index>!" unless range =~ /^(\d+)(-)?(\d*)$/
        raise "Range start cannot be 0 (starts at 1!)" if $1 == "0"
        if $2 == "-"
          if $3
            range = $1.to_i..$2.to_i
          else
            range = $1.to_i..$2.to_i
          end
        else
          range = $1.to_i..$1.to_i
        end

        sandboxes = read_sandboxes

        if sandboxes.any?
          if sandboxes.size > range.max
            info("Showing sandboxes #{range.min} through #{range.max} of #{sandboxes.size} sandboxes")
          else
            info("Showing sandboxes #{range.min} through #{sandboxes.size} (no more sandboxes)")
          end
          sandboxes.each do |handler_id, handler, title, end_time|
            if handler
              status = "running since #{how_long_ago(handler.start_time)}"
            else
              status = "finished at #{how_long_ago(mtime)}."
            end
            info("#{handler.handler_id}: #{status}. <#{config.lita_url}/bumpbot/handlers/#{handler_id}/log|Log> <#{config.lita_url}/bumpbot/handlers/#{handler_id}/download_sandbox|Download Sandbox>. `#{title}`. ")
          end
        else
          info("No sandboxes found!")
        end
      end

      #
      # Helpers (private)
      #

      def read_sandboxes
        if File.directory?(config.sandbox_directory)
          # Get all sandbox directories
          sandboxes = Dir.entries(config.sandbox_directory).select { |entry| File.directory?(entry) && entry =~ /^\d+$/ }
        else
          sandboxes = []
        end

        # Get handler, title and end time
        sandboxes.map! do |handler_id|
          handler,title = running_handlers.find { |handler,title| handler.handler_id == handler_id }
          if handler
            end_time = Time.now.utc
          else
            # This is not currently running. Get status from disk

            # end time is mtime of the logfile
            begin
              end_time = File.mtime(File.join(config.sandbox_directory, handler_id, "handler.log")).utc
            rescue Errno::ENOENT
            end

            # title is first line of the logfile
            title = begin
              line = File.open(File.join(config.sandbox_directory, handler_id)) { |file| file.readline.chomp }
              # Line is [<TIME> - <debug|error|warn|info>] <line>. Just get <line>
              line.split("] ", 2)[1] || line
            rescue Errno::ENOENT
              "(no logfile)"
            end
          end
          [ handler_id.to_i, handler, title, end_time ]
        end

        # Sort in reverse
        sandboxes.sort_by! { |handler_id, handler, title, end_time| end_time }
        sandboxes.reverse!

        sandboxes
      end

      Lita.register_handler(self)
    end
  end
end
