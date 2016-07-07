require "lita"
require "forwardable"
require "tmpdir"
require "fileutils"
require "shellwords"
require "set"
require_relative "../../lita_versioner"
require_relative "../../lita_versioner/format_helpers"
require_relative "../../lita_versioner/handler_output"
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

      attr_reader :output
      attr_reader :response
      attr_accessor :project_name
      attr_reader :start_time
      attr_reader :title

      #
      # Unique ID for the handler
      #
      attr_reader :handler_id

      #
      # Optional command arguments if this handler is a command handler.
      #
      attr_reader :command_args

      #
      # Cache directory for this handler instance
      #
      attr_reader :sandbox_directory

      # Give the handler a monotonically increasing ID
      def initialize(*args)
        super
        @handler_id = redis.incr("max_handler_id")
        @output = LitaVersioner::HandlerOutput.new(self)
      end

      def handler_log_url(id=handler_id)
        "#{config.lita_url}/bumpbot/handlers/#{id}/handler.log"
      end

      # Get the github web URL to the project (strip .git)
      def project_github_url
        if project && project[:github_url]
          if project[:github_url].end_with?(".git")
            project[:github_url[-5..-1]]
          else
            project[:github_url]
          end
        end
      end

      #
      # Create a new handler which will send messages and HTTP responses to the
      # same place as the original.
      #
      # Versioner.from_handler(handler) will create a Versioner object;
      # DependencyUpdater.from_handler(handler) will create a DependencyUpdater
      # object; etc. etc.
      #
      def self.from_handler(handler)
        result = new(handler.robot)
        result.inherit_handler(handler)
        result
      end

      #
      # Inherit response and output information from another handler (see `from_handler`)
      #
      def inherit_handler(handler)
        @project_name = handler.project_name
        @response = handler.response
        output.inherit_output(handler.output)
      end

      #
      # Ensure all subclasses are in the Lita versioner namespace so they share config.
      #
      def self.inherited(klass)
        super
        klass.namespace("versioner")
      end

      extend Forwardable

      # User outputs (Slack)
      def_delegators :output, :respond, :inform, :inform_error, :respond_error!
      # Log outputs
      def_delegators :output, :error, :warn, :info, :debug

      def handle_task(description)
        start_time = Time.now.utc
        debug(description)
        begin
          yield
          debug("Completed #{description} after #{format_duration(Time.now.utc-start_time)}")
        rescue
          error("Failed #{description} after #{format_duration(Time.now.utc-start_time)}: #{$!}")
          raise
        end
      end

      #
      # The Project config for the current project
      #
      def project
        projects[project_name]
      end

      #
      # The full list of configured projects
      #
      def projects
        config.projects
      end

      def log_url
        "#{config.lita_url}/bumpbot/handlers/#{handler_id}/handler.log"
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

      def self.get_desc
        desc = @desc
        @desc = nil
        desc
      end

      def self.desc(desc)
        @desc = desc
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
      #
      def self.command_route(command, help=get_desc, &block)
        help = { "" => help } unless help.is_a?(Hash)

        complete_help = {}
        help.each do |arg, text|
          complete_help["#{command} #{arg}".strip] = text
        end
        regexp = command_regexp(command)
        route(regexp, nil, command: true, help: complete_help) do |response|
          handle_command(command, response, regexp: regexp, help: complete_help, &block)
        end
      end

      #
      # Callback wrapper for handlers.
      #
      # @param title The event title.
      # @return whatever the provided block returns.
      #
      def handle(title, &block)
        if running_handlers.include?(self)
          raise "Cannot call handle or handle_command twice for a single handler! Already running #{self.title.inspect}, but asked to run #{title.inspect}"
        end

        output.lita_target ||= lita_target(nil)
        @title = title
        @start_time = Time.now.utc
        running_handlers << self
        redis.hmset("handlers:#{handler_id}",
                    "title", title,
                    "start_time", start_time.to_i)
        # Assume we will fail, and set the log to expire in failure_ttl
        redis.set("handler_logs:#{handler_id}", "", ex: config.failure_log_ttl)

        output.started
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

        output.finished

      # In case of an error, report it and set result to FAILURE
      rescue
        end_time = Time.now.utc
        begin
          unless ErrorAlreadyReported === $!
            error_string = $!.to_s
            if error_string.include?("\n")
              inform_error("Unhandled error while #{title}: ```#{error_string}```", http_status_code: "500")
            else
              inform_error("Unhandled error while #{title}: #{output.backquote(error_string)}", http_status_code: "500")
            end
            error($!.backtrace.join("\n"))
          end
          debug("Completed #{title} in #{format_duration(end_time - start_time)}")
          output.finished
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
          respond_error!("Read thread exception: #{read_thread_exception}\n#{read_thread_exception.backtrace.map { |l| "  #{l}" }}") if read_thread_exception
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
          respond_error!("Sorry, received HTTP error #{output.backquote(e)} kicking off #{pipeline} build of #{git_ref}")
        end
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

      private

      #
      # Create the regexp for the command.
      #
      def self.command_regexp(command)
        parts = command.split(/\s+/)
        regexp = ""
        parts.each do |part|
          prefix = "\\s+" unless regexp == ""
          case part
          when /^[A-Z_]+$/
            # UPPERCASE is a var.
            regexp << "#{prefix}(?<#{part.downcase}>\\S+)"
          when /^\[([A-Z_]+)\]$/
            # [UPPERCASE] is an optional var
            regexp << "(?:#{prefix}(?<#{$1.downcase}>\\S+))?"
          when /^@USER|#CHANNEL$/
            # @USER|#CHANNEL = "target" var
            regexp << "#{prefix}(?<target>@\\S+|#\\S+)"
          when /^\[@USER|#CHANNEL\]$/
            # [@USER|#CHANNEL] = optional "target" var
            regexp << "(?:#{prefix}(?<target>@\\S+|#\\S+))?"
          else
            regexp << "#{prefix}#{part}"
          end
        end
        Regexp.new("^\s*#{regexp}\s*$")
      end

      def handle_command(command, response, regexp: nil, help: nil, &block)
        @response = response
        output.lita_target = lita_target(response)
        title = "Running `#{response.message.body}` for @#{response.message.source.user.mention_name}"
        # TODO find out how to get the actual channel name instead of the internal ID
        # title << " in ##{response.message.source.room_object.name}" unless response.private_message?
        handle(title) do
          redis.hset("handlers:#{handler_id}", "command", command)
          # Grab the args and the project
          command_args = response.match_data.captures
          project_index = Array(regexp.named_captures["project"]).first
          if project_index
            self.project_name = command_args.delete_at(project_index-1)
            if project_name && !projects.has_key?(project_name)
              respond_error!("Invalid project #{project_name}. Valid projects: #{projects.keys.join(", ")}.\n#{usage(help)}")
            end
          end
          command_args.compact!
          redis.hset("handlers:#{handler_id}", "project", project_name) if project_name
          redis.hset("handlers:#{handler_id}", "command_args", Shellwords.join(command_args))
          instance_exec(*command_args, &block)
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

      def lita_target(response)
        return response.message.source if response
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
