require_relative "error_already_reported"
require_relative "format_helpers"
require_relative "slack_api"
module LitaVersioner
  #
  # Handles the rules for output.
  #
  # The main output methods are logging (debug, info, warn, error) and responses
  # (response, inform_success, inform_error, respond_error!, inform). Responses are sent
  # to Slack as well as the logs.
  #
  # While a handler is running, a special "in progress" message will be shown
  # with the last few lines of log and a link to more. (This will only happen if
  # the handler takes more than 3 seconds to complete.) The in progress message
  # will be updated as we go, and deleted when the operation completes.
  #
  class HandlerOutput
    include FormatHelpers

    # Amount of time to wait (in seconds) before showing the "in progress" message
    SHOW_IN_PROGRESS_AFTER = 3
    # Time between progress log updates
    TIME_BETWEEN_PROGRESS_LOG_UPDATES = 0.1
    # Number of log lines to show in the "in progress" message.
    SHOW_LOG_LINES = 10

    def initialize(handler)
      @handler = handler
      @progress_message_mutex = Mutex.new
    end

    attr_reader :handler
    attr_accessor :lita_target
    attr_accessor :http_response
    attr_accessor :status

    def slack_api
      if Lita.config.robot.adapter == :slack
        SlackAPI.new(handler.robot.config)
      end
    end

    # Let the user know something about the operation.
    def inform(message = nil, http_status_code: nil, **slack_message_arguments)
      # Send data to HTTP response
      if http_response
        http_response.status = http_status_code if http_status_code
        slack_to_messages(message, **slack_message_arguments).each do |message|
          http_response.body << (message.end_with?("\n") ? message : "#{message}\n")
        end
      end

      # Send a message
      send_message(message, **slack_message_arguments)

      # Log to info log
      info(message) if message
    end

    # Give the user a success message.
    def inform_success(message = nil, http_status_code: nil, **slack_message_arguments)
      self.status = :succeeded
      # Status has changed; update the progress message.
      update_progress_message
      # Format message as attachment with green
      if message
        slack_message_arguments[:attachments] = Array(slack_message_arguments[:attachments])
        slack_message_arguments[:attachments] << {
          color: "good",
          text: message,
          mrkdwn_in: [ "text" ],
        }
      end
      inform(http_status_code: http_status_code, **slack_message_arguments)
    end
    alias_method :respond, :inform_success

    # Let the user know about an error.
    def inform_error(message = nil, http_status_code: nil, **slack_message_arguments)
      self.status = :failed
      # Status has changed; update the progress message.
      update_progress_message

      # Send data to HTTP response
      if http_response
        http_response.status = http_status_code if http_status_code
        slack_to_messages(message, **slack_message_arguments).each do |message|
          http_response.body << (message.end_with?("\n") ? message : "#{message}\n")
        end
      end

      # Format and send message
      if message
        slack_message_arguments[:attachments] = Array(slack_message_arguments[:attachments])
        slack_message_arguments[:attachments] << {
          color: "danger",
          text: "#{message}",
          ts: handler.start_time,
          footer: "#{(status || "In progress").capitalize}. <#{handler.log_url}|Full log available here.>",
          mrkdwn_in: [ "text" ],
        }
      end
      send_message(**slack_message_arguments)

      # Log to error log
      error(message)

      update_progress_message
    end

    # Let the user know about the error, and raise the error.
    def respond_error!(message, http_status_code: nil, **slack_message_arguments)
      inform_error(message, http_status_code: http_status_code, **slack_message_arguments)
      raise ErrorAlreadyReported.new(message)
    end

    # Log an error.
    def error(message)
      log(:error, message)
    end

    # Log a warning.
    def warn(message)
      log(:warn, message)
    end

    # Log an informational message.
    def info(message)
      log(:info, message)
    end

    # Log a debug message.
    def debug(message)
      log(:debug, message)
    end

    # Used to let us know the handler has officially started and is set up
    def started
      self.status = nil
      # Set the in progress message if we're still running after a while
      Thread.new do
        begin
          sleep SHOW_IN_PROGRESS_AFTER
          create_progress_message
        rescue
          error("Could not create progress message: #{$!}\n#{$!.backtrace.join("\n")}")
          raise
        end
      end
    end

    # Used to let us know the handler is officially complete
    def finished
      self.status ||= :skipped
      update_progress_message
    end

    def escape_markdown(text)
      text = text.gsub("&", "&amp;")
      text.gsub!("<", "&lt;")
      text.gsub!(">", "&gt;")
      text.gsub!(%r{[`*_|=]}) { |c| "&##{c.bytes[0]};" }
      text
    end

    def backquote(text)
      # Haven't figured out a way to backquote a backquote in markdown
      "`#{text.tr("`", "'")}`"
    end

    private

    attr_accessor :last_log_time
    attr_accessor :last_log_level

    #
    # Log the line to lita, redis and store the last few for the progress message.
    #
    # Adds prefixes to each to do things like identify the handler or log level.
    #
    def log(log_level, message)
      message_lines = message.to_s.lines
      time = Time.now.utc.to_s

      # Store in redis
      log_time = time.to_s
      justified_log_level = log_level.to_s.upcase.ljust(5)
      log_chunk = message_lines.map do |line|
        # After the first line of the output, emit spaces for easier reading
        if log_time == last_log_time
          log_time = " " * log_time.size if log_time == last_log_time
        else
          self.last_log_time = log_time
        end
        if justified_log_level == last_log_level
          justified_log_level = " " * justified_log_level.size if justified_log_level == last_log_level
        else
          self.last_log_level = justified_log_level
        end
        "[#{log_time} #{justified_log_level}] #{line.chomp}\n"
      end.join("")
      handler.redis.append("handler_logs:#{handler.handler_id}", log_chunk)

      # Send to lita log
      message_lines.each do |l|
        handler.log.public_send(log_level, "[#{handler.handler_id}] #{l.chomp}")
      end

      # Keep last n lines in progress message
      @progress_log = (progress_log + message_lines).last(SHOW_LOG_LINES).map { |l| l.chomp }
      unless last_progress_message_update && (Time.now.utc - last_progress_message_update) < TIME_BETWEEN_PROGRESS_LOG_UPDATES
        update_progress_message
      end
    end

    #
    # Send a message to the appropriate place.
    #
    # - For Slack messages, errors are sent to the originating user via respond
    # - For events, errors are sent to the project.channel_name
    #
    def send_message(message = nil, link_names: 1, parse: "none", **slack_message_arguments)
      slack_message_arguments[:link_names] = link_names
      slack_message_arguments[:parse] = parse
      if lita_target
        if slack_api
          slack_api.post("chat.postMessage", channel: lita_target, text: message, **slack_message_arguments)
        else
          slack_to_messages(message, **slack_message_arguments).each do |message|
            handler.robot.send_message(lita_target, message)
          end
        end
      end
    end

    def slack_to_messages(message = nil, **slack_message_arguments)
      messages = []
      messages << message if message
      if slack_message_arguments[:attachments]
        slack_message_arguments[:attachments].each do |attachment|
          if attachment[:fallback]
            messages << attachment[:fallback]
          else
            messages << attachment[:title] if attachment[:title]
            messages << attachment[:text] if attachment[:text]
            messages << attachment[:footer] if attachment[:footer]
          end
        end
      end
      messages
    end

    #
    # Progress implementation: inform users of handler progress if handlers run
    # for too long.
    #

    attr_reader :progress_message_mutex
    attr_accessor :last_progress_message_update
    attr_accessor :progress_message_channel
    attr_accessor :progress_message_ts
    def progress_log
      @progress_log ||= []
    end

    def progress_message(footer_suffix = "")
      attachment =  {
        fallback: "#{(status || "In progress").capitalize}: #{handler.title}",
        title: "#{(status || "In progress").capitalize}: #{handler.title}",
        ts: handler.start_time.to_i,
        mrkdwn_in: ["text"],
      }

      # Do not show the log inline if we're sending to a channel. Only in PM.
      unless lita_target.is_a?(Lita::Room)
        log = progress_log.join("\n")
        log = "```#{log}```" unless log.empty?
        attachment[:text] = log
      end

      # Color the attachment based on status
      case status
      when :failed
        attachment[:color] = "danger"
      when :succeeded
        attachment[:color] = "good"
      when :skipped
      else
        # In progress
        attachment[:footer] = "#{(status || "In progress").capitalize}. <#{handler.log_url}|Full log available here.> This message will self-destruct."
        attachment[:color] = "warning"
      end

      {
        attachments: [ attachment ],
      }
    end

    # Create the progress message in Slack. This happens after the command has
    # been running for a while.
    def create_progress_message
      progress_message_mutex.synchronize do
        # Only create the log if we're in progress.
        if status.nil?
          if lita_target && slack_api
            # Remember the id (channel + ts) of the message we create
            response = slack_api.post("chat.postMessage", channel: lita_target, **progress_message)
            self.last_progress_message_update = Time.now.utc
            self.progress_message_channel = response["channel"]
            self.progress_message_ts = response["ts"]
          end
        end
      end
    end

    # Update the progress message in Slack (if it's there). If the command is
    # finished, this deletes it.
    def update_progress_message
      # We synchronize the mutex to eliminate race conditions where the message
      # is created after we've made the decision to delete them, or we attempt
      # to update a message that's already been deleted.
      progress_message_mutex.synchronize do
        if progress_message_ts
          if status
            # If we're finished, delete the progress message. Presumably the
            # command has emitted a success or failure message.
            slack_api.post("chat.delete", channel: progress_message_channel, ts: progress_message_ts)
            self.progress_message_channel = nil
            self.progress_message_ts = nil
          else
            # Otherwise, update it.
            slack_api.post("chat.update", channel: progress_message_channel, ts: progress_message_ts, **progress_message)
          end
          self.last_progress_message_update = Time.now.utc
        end
      end
    end
  end
end
