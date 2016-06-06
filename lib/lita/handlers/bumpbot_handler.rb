require "lita"
require "forwardable"
require "tmpdir"
require "fileutils"
require_relative "../../lita_versioner"
require_relative "../../lita_versioner/format_helpers"
require_relative "../../lita_versioner/jenkins_http"
require "shellwords"

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

      attr_accessor :project_name
      attr_reader :response
      attr_accessor :http_response
      attr_reader :start_time

      #
      # Unique ID for the handler
      #
      attr_reader :handler_id

      def self.inherited(klass)
        super
        klass.namespace("versioner")
      end

      @@handler_id = 0
      @@handler_mutex = Mutex.new
      def handler_mutex
        @@handler_mutex
      end

      # Give the handler a monotonically increasing ID
      def initialize(*args)
        super
        @log_mutex = Mutex.new
        handler_mutex.synchronize do
          @@handler_id += 1
          @handler_id = @@handler_id.to_s
        end
      end

      #
      # Synchronizes log access so we don't get lines on top of each other
      #
      attr_reader :log_mutex

      def project_repo
        @project_repo ||= ProjectRepo.new(self)
      end

      def cleanup
        FileUtils.rm_rf(sandbox_directory)
        debug("Cleaned up sandbox directory after successful command")
      end

      @@running_handlers = {}
      def running_handlers
        @@running_handlers
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
      # Cache directory for this handler instance to
      #
      def sandbox_directory
        @sandbox_directory ||= begin
          dir = File.join(config.sandbox_directory, handler_id)
          FileUtils.rm_rf(dir)
          FileUtils.mkdir_p(dir)
          dir
        end
      end

      #
      # The log file we write messages to for this handler
      #
      def logfile
        File.join(sandbox_directory, "handler.log")
      end

      #
      # Callback wrapper for non-command handlers.
      #
      # @param title The event title.
      # @return whatever the provided block returns.
      #
      def handle_event(title)
        raise "Cannot call handle_event or handle_command twice for a single handler! Already running #{running_handlers[self].inspect}, and asked to run #{running_handlers[self].inspect}" if running_handlers[self]

        running_handlers[self] = title
        @start_time = Time.now.utc
        @response = nil
        debug("Start event #{running_handlers[self]} - handler id #{handler_id} sandbox #{sandbox_directory}")
        yield
        cleanup
      rescue ErrorAlreadyReported
      rescue
        msg = "Unhandled error while working on \"#{title}\":\n" +
          "```#{$!}\n#{$!.backtrace.join("\n")}."
        error(msg)
      ensure
        debug("Completed event #{running_handlers[self]} in #{format_duration(Time.now.utc - start_time)} - handler id #{handler_id} sandbox #{sandbox_directory}")
        running_handlers.delete(self)
      end

      #
      # Run a command (and report the output)
      #
      def run_command(command, timeout: 3600, **options)
        command_start_time = Time.now.utc
        Bundler.with_clean_env do
          options[:timeout] = timeout

          command = Shellwords.join(command) if command.is_a?(Array)
          debug("`#{command}` starting with #{options}")
          shellout = Mixlib::ShellOut.new(command, options)
          shellout.run_command
          debug("Completed `#{command}` with status #{shellout.exitstatus} in #{format_duration(Time.now.utc - command_start_time)}")
          shellout.error!
          debug("STDOUT:\n```#{shellout.stdout}```\n") if shellout.stdout != ""
          debug("STDERR:\n```#{shellout.stderr}```\n") if shellout.stderr != ""
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
        raise "Cannot call handle_event or handle_command twice for a single handler! Already running #{running_handlers[self].inspect}, and asked to run #{running_handlers[self].inspect}" if running_handlers[self]

        @start_time = Time.now.utc
        @response = response

        running_handlers[self] = "command #{command.inspect} from #{response.message.source.user.mention_name}#{response.message.source.room ? " in #{response.message.source.room}" : ""}"
        debug("Starting #{running_handlers[self]}")
        begin
          parse_args(command, response, **arg_options)
          instance_exec(*command_args, &block)
          cleanup
        rescue ErrorAlreadyReported
        rescue
          msg = "Unhandled error while working on \"#{response.message.body}\":\n" +
            "```#{$!}\n#{$!.backtrace.join("\n")}```."
          error(msg)
        ensure
          debug("Completed #{running_handlers[self]} in #{format_duration(Time.now.utc - start_time)}")
          running_handlers.delete(self)
        end
      end

      def parse_args(command, response, help: help, project_arg: true, max_args: 0)
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
        log_mutex.synchronize do
          File.open(logfile, "a") do |file|
            log_time = time.to_s
            justified_log_level = log_level.to_s.upcase.ljust(5)
            message.to_s.each_line do |line|
              # After the first line of the output, emit spaces for easier reading
              if log_time == last_log_time
                log_time = " " * log_time.size if log_time == last_log_time
              else
                self.last_log_time = log_time
              end
              if log_level == justified_log_level
                justified_log_level = " " * justified_log_level.size if justified_log_level == last_log_level
              else
                self.last_log_level = justified_log_level
              end
              file.puts("[#{log_time} #{justified_log_level}] #{line.chomp}")
            end
          end
        end
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

      Lita.register_handler(self)
    end
  end
end
