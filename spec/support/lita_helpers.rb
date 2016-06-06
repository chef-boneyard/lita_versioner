require "lita"
require "lita/handlers/bumpbot_handler"

module LitaHelpers
  # Create a notifications room to receive notifications from event handlers
  def self.included(other)
    other.class_eval do
      let(:notifications_room) { Lita::Room.create_or_update("#notifications") }

      before do
        allow_any_instance_of(Lita::Handlers::BumpbotHandler).to receive(:source_by_name) { |name| notifications_room }

        lita_config = Lita.config.handlers.versioner
        lita_config.jenkins_username = "ci"
        lita_config.jenkins_api_token = "ci_api_token"
        lita_config.trigger_real_builds = true
        lita_config.cache_directory = File.join(tmpdir, "cache")
        lita_config.sandbox_directory = File.join(lita_config.cache_directory, "sandbox")
        lita_config.debug_lines_in_pm = false
        lita_config.default_inform_channel = "default_notifications"
        lita_config.polling_interval = nil
      end
    end
  end

  def reply_lines
    replies.flat_map { |r| r.lines }.map { |l| l.chomp }
  end

  def reply_string
    reply_lines.map { |l| "#{l}\n" }.join("")
  end
end

module Lita
  module Handlers
    class TestWaitHandler < BumpbotHandler
      command_route "test wait", "Waits until signalled.", max_args: 1, project_arg: false do |failure|
        wait_for.wait(mutex)
        error!(failure) if failure
      end

      def initialize(*args)
        super
        # There has to be a mutex so the signalling can happen
        @mutex = Mutex.new
        mutex.lock
        @wait_for = ConditionVariable.new
      end

      attr_reader :mutex
      attr_reader :wait_for

      def stop
        mutex.synchronize { wait_for.signal }
      end
    end

    class TestCommandHandler < BumpbotHandler
      command_route "test command", "Runs through, or fails if given a message to fail with.", max_args: 1, project_arg: false do |failure|
        error!(failure) if failure
      end
    end
  end
end
