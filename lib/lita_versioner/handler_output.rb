require_relative "error_already_reported"
require_relative "format_helpers"

module LitaVersioner
  class HandlerOutput
    include FormatHelpers

    def initialize(handler)
      @handler = handler
    end

    attr_reader :handler
    attr_accessor :lita_target
    attr_accessor :http_response

    # Let the user know something about the operation.
    def inform(message=nil, http_status_code: nil, parse: "none", **slack_message_arguments)
      # Send data to HTTP response
      if http_response
        http_response.status = http_status_code if http_status_code
        message = "#{message}\n" unless message.end_with?("\n")
        http_response.body << message
      end

      # Send a message
      send_message(message, **slack_message_arguments)
    end
    alias_method :respond, :inform

    # Let the user know about an error.
    def inform_error(message=nil, http_status_code: nil, **slack_message_arguments)
      if message
        slack_message_arguments[:attachments] = Array(slack_message_arguments[:attachments])
        slack_message_arguments[:attachments] << { color: "danger", text: message }
      end
      inform(http_status_code: http_status_code, **slack_message_arguments)
      error(message)
    end

    # Let the user know about the error, and raise the error.
    def error!(message, http_status_code: nil, **slack_message_arguments)
      inform_error(message, http_status_code: http_status_code, **slack_message_arguments)
      raise ErrorAlreadyReported.new(message)
    end

    def error(message)
      log(:error, message)
    end
    def warn(message)
      log(:warn, message)
    end
    def info(message)
      log(:info, message)
    end
    def debug(message)
      log(:debug, message)
    end

    private

    attr_accessor :last_log_time
    attr_accessor :last_log_level

    #
    # Log to the default Lita logger with a custom per-line prefix.
    #
    # This is help identify what command or handler a particular message came
    # from when reading syslog.
    #
    def log(log_level, message)
      time = Time.now.utc.to_s

      log_time = time.to_s
      justified_log_level = log_level.to_s.upcase.ljust(5)
      log_chunk = message.to_s.lines.map do |line|
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

      message.to_s.each_line do |l|
        handler.log.public_send(log_level, "[#{handler.handler_id}] #{l.chomp}")
      end
    end

    #
    # Send a message to the appropriate place.
    #
    # - For Slack messages, errors are sent to the originating user via respond
    # - For events, errors are sent to the project.channel_name
    #
    def send_message(message=nil, **message_arguments)
      if lita_target
        if Lita.config.robot.adapter == :slack
          if message
            handler.robot.chat_service.send_message(lita_target, message, **message_arguments)
          else
            handler.robot.chat_service.send_message(lita_target, **message_arguments)
          end
        else
          handler.robot.send_message(lita_target, message) if message
          if message_arguments[:attachments]
            message_arguments[:attachments].each do |attachment|
              handler.robot.send_message(attachment[:pretext]) if attachment[:pretext]
              handler.robot.send_message(attachment[:text]) if attachment[:text]
            end
          end
        end
      end
    end
  end
end
