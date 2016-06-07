require "lita"
require "forwardable"
require "tmpdir"
require "fileutils"
require "shellwords"
require "set"
require_relative "../../lita_versioner"
require_relative "../../lita_versioner/format_helpers"
require_relative "../../lita_versioner/jenkins_http"

module Lita
  module Handlers
    class BumpbotHandler < Handler
      # include LitaVersioner so we get the constants from it (so we can use the
      # classes easily here and in subclasses)
      include LitaVersioner
      include LitaVersioner::FormatHelpers

      namespace "versioner"

      config :jenkins_username, required: true
      config :jenkins_api_token, required: true
      config :jenkins_endpoint, default: "http://manhattan.ci.chef.co/"
      config :polling_interval, default: false
      config :trigger_real_builds, default: false
      config :default_inform_channel, default: "chef-notify"
      config :projects, default: {}
      config :cache_directory, default: "#{Dir.tmpdir}/lita_versioner"
      config :sandbox_directory, default: "#{Dir.tmpdir}/lita_versioner/sandbox"
      config :debug_lines_in_pm, default: true
      config :lita_url, required: true
      config :success_log_ttl, default: 60 * 60 * 24 * 7
      config :failure_log_ttl, default: 60 * 60 * 24 * 60

      attr_accessor :project_name
      attr_reader :response
      attr_accessor :http_response
      attr_reader :start_time
      attr_reader :title

      #
      # Unique ID for the handler
      #
      attr_reader :handler_id

      def self.inherited(klass)
        super
        klass.namespace("versioner")
      end

      def self.reset!
        @@running_handlers = Set.new
      end
      reset!

      def self.running_handlers
        @@running_handlers
      end

      def running_handlers
        @@running_handlers
      end

      # Give the handler a monotonically increasing ID
      def initialize(*args)
        super
        @handler_id = redis.incr("max_handler_id")
      end

      #
      # Synchronizes log access so we don't get lines on top of each other
      #
      def project_repo
        @project_repo ||= ProjectRepo.new(self)
      end

      def remove_sandbox_directory
        FileUtils.rm_rf(sandbox_directory)
        debug("Cleaned up sandbox directory #{sandbox_directory} after successful command ...")
      end

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

      #
      # Cache directory for this handler instance
      #
      attr_reader :sandbox_directory

      #
      # Callback wrapper for handlers.
      #
      # @param title The event title.
      # @return whatever the provided block returns.
      #
      def handle(title, response: nil, &block)
        if running_handlers.include?(self)
          raise "Cannot call handle_event or handle_command twice for a single handler! Already running #{title.inspect}, and asked to run #{self.title.inspect}"
        end

        @title = title
        @start_time = Time.now.utc
        @response = response
        running_handlers << self
        redis.hmset("handlers:#{handler_id}",
                    "title", title,
                    "start_time", start_time.to_i)
        # Assume we will fail, and set the log to expire in failure_ttl
        redis.set("handler_logs:#{handler_id}", "", ex: config.failure_log_ttl)

        create_sandbox_directory
        debug("Started #{title}")

        # Actually handler the command
        instance_eval(&block)

        end_time = Time.now.utc
        debug("Completed #{title} in #{format_duration(end_time - start_time)}")
        remove_sandbox_directory

        redis.hmset("handlers:#{handler_id}",
                    "end_time", end_time.to_i)
        # Set successful logs to expire earlier
        redis.expire("handler_logs:#{handler_id}", config.success_log_ttl)

      # In case of an error, report it and set result to FAILURE
      rescue
        end_time = Time.now.utc
        begin
          unless ErrorAlreadyReported === $!
            msg = "Unhandled error while #{title}:\n" +
              "```#{$!}\n#{$!.backtrace.join("\n")}```."
            error(msg)
          end
          debug("Completed #{title} in #{format_duration(end_time - start_time)}")
        ensure
          # Even if the act of reporting the error raises, we want to set the
          # command finished (if we can).
          redis.hmset("handlers:#{handler_id}",
                      "end_time", end_time.to_i,
                      "failed", "1")
        end
      ensure
        running_handlers.delete(self)
      end

      #
      # Run a command (and report the output)
      #
      def run_command(command, **options)
        command_start_time = Time.now.utc
        command = Shellwords.join(command) if command.is_a?(Array)

        Bundler.with_clean_env do
          read_thread_exception = nil
          begin
            # Listen for output from the command
            read, write = IO.pipe
            read_thread = Thread.new do
              begin
                buf = ""
                # We want to read *up to* 32K, but we want to read as quick as we can.
                loop do
                  begin
                    read.readpartial(32 * 1024, buf)
                    debug(buf)
                  rescue EOFError
                    break
                  end
                end
              rescue
                read_thread_exception = $!
              end
            end

            # Start the command
            debug("`#{command}` starting#{" with #{options.map { |k, v| "#{k}=#{v}" }.join(", ")}" if options}")
            shellout = Mixlib::ShellOut.new(command, live_stream: write, timeout: 3600, **options)
            shellout.run_command
          ensure
            # Command is finished one way or the other. Close out the pipe and
            # wait for it to output.
            write.close if write
            read_thread.join if read_thread
          end

          debug("Completed `#{command}` with status #{shellout.exitstatus} in #{format_duration(Time.now.utc - command_start_time)}")
          shellout.error!
          error!("Read thread exception: #{read_thread_exception}\n#{read_thread_exception.backtrace.map { |l| "  #{l}" }}") if read_thread_exception
          shellout
        end
      end

      #
      # Trigger a Jenkins build on the given git ref.
      #
      def trigger_build(pipeline, git_ref)
        debug("Kicking off a build for #{pipeline} at ref #{git_ref}.")

        unless config.trigger_real_builds
          warn("Would have triggered a build, but config.trigger_real_builds is false.")
          return true
        end

        jenkins = JenkinsHTTP.new(base_uri: config.jenkins_endpoint,
                                  username: config.jenkins_username,
                                  api_token: config.jenkins_api_token)

        begin
          jenkins.post("/job/#{pipeline}/buildWithParameters",
            "GIT_REF" => git_ref,
            "EXPIRE_CACHE" => false,
            "INITIATED_BY" => response ? response.user.mention_name : "BumpBot"
          )
        rescue JenkinsHTTP::JenkinsHTTPError => e
          error("Sorry, received HTTP error when kicking off the build!\n#{e}")
          return false
        end

        return true
      end

      #
      # Optional command arguments if this handler is a command handler.
      #
      attr_reader :command_args

      def error!(message, status: "500")
        error(message, status: status)
        raise ErrorAlreadyReported.new(message)
      end

      def error(message, status: "500")
        if http_response
          http_response.status = status
        end
        send_message("**ERROR:** #{message}")
        log_each_line(:error, message)
      end

      def warn(message)
        send_message("WARN: #{message}")
        log_each_line(:warn, message)
      end

      def info(message)
        send_message(message)
        log_each_line(:info, message)
      end

      # debug messages are only sent to users in private messages
      def debug(message)
        send_message(message) if response && response.private_message? && config.debug_lines_in_pm
        log_each_line(:debug, message)
      end

      def project
        projects[project_name]
      end

      def projects
        config.projects
      end

      class ErrorAlreadyReported < StandardError
        attr_accessor :cause

        def initialize(message = nil, cause = nil)
          super(message)
          self.cause = cause
        end
      end

      private

      def handle_command(command, response, **arg_options, &block)
        handle("handling command #{response.message.body.inspect} from #{response.message.source.user.mention_name}#{response.message.source.room ? " in #{response.message.source.room}" : ""}", response: response) do
          redis.hset("handlers:#{handler_id}", "command", command)
          parse_args(command, response, **arg_options)
          redis.hset("handlers:#{handler_id}", "project", project_name) if project_name
          redis.hset("handlers:#{handler_id}", "command_args", Shellwords.join(command_args))
          instance_exec(*command_args, &block)
        end
      end

      def parse_args(command, response, help:, project_arg: true, max_args: 0)
        # Strip extra words from the args: response.args will start with
        # "dependencies" if the command is "update dependencies"
        command_words = command.split(/\s+/)
        args = response.args[command_words.size - 1..-1]

        if project_arg
          # Grab the project name and command args
          @project_name = args.shift
          error!("No project specified!\n#{usage(help)}") unless project_name
          unless project
            error!("Invalid project #{project_name}. Valid projects: #{projects.keys.join(", ")}.\n#{usage(help)}")
          end
        end

        @command_args = args

        if command_args.size > max_args
          error!("Too many arguments (#{command_args.size + (project_arg ? 1 : 0)} for #{max_args + (project_arg ? 1 : 0)})!\n#{usage(help)}")
        end
      end

      #
      # Usage for this command.
      #
      def usage(help)
        usage = "Usage: "
        usage << "\n" if help.size > 1
        usage_lines = help.map { |command, text| "#{command}   - #{text}" }
        usage << usage_lines.join("\n")
      end

      attr_accessor :last_log_time
      attr_accessor :last_log_level

      #
      # Log to the default Lita logger with a custom per-line prefix.
      #
      # This is help identify what command or handler a particular message came
      # from when reading syslog.
      #
      def log_each_line(log_level, message)
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
        redis.append("handler_logs:#{handler_id}", log_chunk)

        message.to_s.each_line do |l|
          log.public_send(log_level, "[#{handler_id}] #{l.chomp}")
        end
      end

      #
      # Send a message to the appropriate place.
      #
      # - For Slack messages, errors are sent to the originating user via respond
      # - For events, errors are sent to the project.channel_name
      #
      def send_message(message)
        if response
          response.reply(message)
        else
          room = message_source
          robot.send_message(room, message) if room
        end
        if http_response
          message = "#{message}\n" unless message.end_with?("\n")
          http_response.body << message
        end
      end

      def message_source
        if project && project[:inform_channel]
          @project_room = source_by_name(project[:inform_channel]) unless defined?(@project_room)
          @project_room
        else
          @default_room = source_by_name(config.default_inform_channel) unless defined?(@default_room)
          @default_room
        end
      end

      def source_by_name(channel_name)
        room = Lita::Room.fuzzy_find(channel_name)
        source = Lita::Source.new(room: room) if room
        log_each_line(:error, "Unable to resolve ##{channel_name}.") unless source
        source
      end

      def create_sandbox_directory
        @sandbox_directory = begin
          dir = File.join(config.sandbox_directory, handler_id.to_s)
          FileUtils.rm_rf(dir)
          FileUtils.mkdir_p(dir)
          dir
        end
      end

      Lita.register_handler(self)
    end
  end
end
