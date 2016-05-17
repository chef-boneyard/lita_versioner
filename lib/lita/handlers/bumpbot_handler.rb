require "forwardable"

module Lita
  module Handlers
    class BumpbotHandler < Handler
      config :jenkins_username, required: true
      config :jenkins_api_token, required: true
      config :jenkins_endpoint, default: "http://manhattan.ci.chef.co/"
      config :polling_interval, default: false
      config :trigger_real_builds, default: false
      config :default_inform_channel, default: "eng-services-support"
      config :projects, default: {}

      namespace "versioner"

      attr_accessor :project_name
      attr_reader :handler_name
      attr_reader :response

      def self.inherited(klass)
        super
        klass.namespace("versioner")
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
      # @param max_args [Int] Maximum number of extra arguments that this command takes.
      #
      def self.command_route(command, method_sym, help, max_args = 0)
        complete_help = {}
        help.each do |arg, text|
          complete_help["#{command} PROJECT #{arg}".strip] = text
        end
        route(/^#{command}\b/, nil, command: true, help: complete_help) do |response|
          # This block will be instance-evaled in the context of the handler
          # instance - so we can set instance variables etc.
          begin
            init_command(command, response, complete_help, max_args)
            public_send(method_sym)
          rescue ErrorAlreadyReported
            error("Aborting bump bot command \"#{response.message.body}\" due to previously raised error")
          rescue
            msg = "Unhandled error while working on \"#{response.message.body}\":\n" +
              "```#{$!}\n#{$!.backtrace.join("\n")}```"
            error(msg)
          end
        end
      end

      #
      # Callback wrapper for non-command handlers.
      #
      # @param title The event title.
      # @return whatever the provided block returns.
      #
      def handle_event(title)
        init_event(title)
        yield
      rescue ErrorAlreadyReported
        error("Aborting message handler \"#{title}\" due to previously raised error")
      rescue
        msg = "Unhandled error while working on \"#{title}\":\n" +
          "```#{$!}\n#{$!.backtrace.join("\n")}"
        error(msg)
      end

      def run_command(command, timeout: 3600, **options)
        Bundler.with_clean_env do
          options[:timeout] = timeout
          options[:live_stream] = $stdout if Lita.logger.debug? && !options.has_key?(:live_stream)

          debug("Running \"#{command}\" with #{options}")
          shellout = Mixlib::ShellOut.new(command, options)
          shellout.run_command
          shellout.error!
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
                                  usernme: config.jenkins_username,
                                  api_token: config.jenkins_api_token)

        begin
          jenkins.post("/job/#{pipeline}/buildWithParameters",
            "GIT_REF" => git_ref,
            "EXPIRE_CACHE" => false,
            "INITIATED_BY" => response ? response.user.mention_name : "BumpBot"
          )
        rescue JenkinsHTTPError => e
          error("Sorry, received HTTP error when kicking off the build!\n#{e}")
          return false
        end

        return true
      end

      #
      # Optional command arguments if this handler is a command handler.
      #
      def command_args
        @command_args ||= response.args.drop(1) if response
      end

      def error!(message)
        error(message)
        raise ErrorAlreadyReported.new(message)
      end

      def error(message)
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
        send_message(message) if response && response.private_message?
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

      #
      # Initialize this handler as a chat command handler.
      #
      def init_command(command, response, help, max_args)
        @handler_name = command
        @response = response
        error!("No project specified!\n#{usage(help)}") if response.args.empty?
        @project_name = response.args[0]
        debug("Starting")
        unless project
          error!("Invalid project. Valid projects: #{projects.keys.join(", ")}.\n#{usage(help)}")
        end
        if command_args.size > max_args
          error!("Too many arguments (#{command_args.size + 1} for #{max_args + 1})!\n#{usage(help)}")
        end
      end

      #
      # Initialize this handler as a chat command handler.
      #
      def init_event(name)
        @handler_name = name
        @response = nil
        debug("Starting")
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

      #
      # Log to the default Lita logger with a custom per-line prefix.
      #
      # This is help identify what command or handler a particular message came
      # from when reading syslog.
      #
      def log_each_line(log_method, message)
        prefix = "<#{handler_name}>{#{project_name || "unknown"}} "
        message.to_s.each_line do |l|
          log.public_send(log_method, "#{prefix}#{l.chomp}")
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
        source = Source.new(room: room) if room
        log_each_line(:error, "Unable to resolve ##{channel_name}.") unless source
        source
      end
    end

    Lita.register_handler(BumpbotHandler)
  end
end
