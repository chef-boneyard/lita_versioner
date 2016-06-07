require "spec_helper"
require "tmpdir"
require "fileutils"

describe Lita::Handlers::BumpbotStatusHandler, lita_handler: true, additional_lita_handlers: [ Lita::Handlers::BumpbotStatusWebpageHandler, Lita::Handlers::BumpbotHandler, Lita::Handlers::TestWaitHandler, Lita::Handlers::TestCommandHandler ] do
  include LitaHelpers

  # Initialize lita
  before do
    Lita.config.handlers.versioner.projects = {
      "lita-test" => {
        pipeline: "lita-test-trigger-release",
        github_url: git_remote,
        version_bump_command: "cat a.txt",
        version_show_command: "cat a.txt",
        dependency_update_command: "cat a.txt",
        inform_channel: "notifications",
      },
    }
  end

  let(:git_remote) { File.join(tmpdir, "lita-test") }

  # Create a repository with file.txt = A, deps.txt=X
  attr_reader :initial_commit_sha
  before do
    create_remote_git_repo(git_remote, "a.txt" => "A")
    @initial_commit_sha = git_sha(git_remote)
  end

  TIMESTAMP_SIZE = "2016-06-07 02:45:52 UTC ".size
  def strip_log_data(log)
    log = log.gsub(/^\[.{#{TIMESTAMP_SIZE}}/, "[")
    log.gsub(tmpdir, "/TMPDIR")
  end

  with_jenkins_server "http://manhattan.ci.chef.co"

  context "bumpbot handlers" do
    it "bumpbot running handlers with arguments emits a reasonable error message" do
      send_command("bumpbot running handlers blarghle")

      expect(reply_string).to eq(strip_eom_block(<<-EOM))
        **ERROR:** Too many arguments (1 for 0)!
        Usage: bumpbot running handlers   - Get the list of running handlers in bumpbot
      EOM
    end

    it "bumpbot handlers with more than one argument emits a reasonable error message" do
      send_command("bumpbot handlers 1-2 blarghle")

      expect(reply_string).to eq(strip_eom_block(<<-EOM))
        **ERROR:** Too many arguments (2 for 1)!
        Usage: bumpbot handlers [RANGE]   - Get the list of running and failed handlers in bumpbot (corresponds to the list of failed commands). Optional RANGE will get you a list of handlers. Default range is 1-10.
      EOM
    end

    context "when there are no running handlers" do
      it "bumpbot running handlers reports no handlers" do
        send_command("bumpbot running handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          No command or event handlers are running right now.
        EOM
      end

      it "bumpbot handlers reports no handlers" do
        send_command("bumpbot handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          The system is not running any handlers, and nothing has failed, so there is no handler history to show.
        EOM
      end
    end

    context "when a handler is running" do
      before do
        @handler_thread = Thread.new { send_command("test wait") }
        loop do
          @handler = Lita::Handlers::BumpbotHandler.running_handlers.find { |handler| handler.is_a?(Lita::Handlers::TestWaitHandler) }
          break if @handler
          sleep(0.05)
        end
      end

      attr_reader :handler_thread
      attr_reader :handler

      it "bumpbot running handlers shows it" do
        send_command("bumpbot running handlers")

        handler.stop
        handler_thread.join

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          handling command "test wait" from Test User running since just now. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "bumpbot running handlers shows 2 seconds ago after 2 seconds" do
        sleep(2)
        send_command("bumpbot running handlers")
        handler.stop
        handler_thread.join

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          handling command "test wait" from Test User running since 2 seconds ago. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "bumpbot handlers shows it" do
        send_command("bumpbot handlers")

        handler.stop
        handler_thread.join

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          handling command "test wait" from Test User running since just now. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "bumpbot handlers shows 2 seconds ago after 2 seconds" do
        sleep(2)
        send_command("bumpbot handlers")
        handler.stop
        handler_thread.join

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          handling command "test wait" from Test User running since 2 seconds ago. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "GET /bumpbot/handlers/1/handler.log streams the response" do
        response = nil
        get_thread = Thread.new { response = http.get("/bumpbot/handlers/1/handler.log") }

        # Wait long enough that the response would close if it exited early
        sleep(0.2)
        handler.stop
        handler_thread.join
        get_thread.join

        expect(response.status).to eq(200)
        expect(strip_log_data(response.body)).to eq(strip_eom_block(<<-EOM))
          [DEBUG] Started handling command "test wait" from Test User
          [     ] Completed handling command "test wait" from Test User in 00:00:00
          [     ] Cleaned up sandbox directory /TMPDIR/cache/sandbox/1 after successful command ...
        EOM
      end
    end

    context "when a handler has already completed successfully" do
      before do
        send_command("test command")
      end

      it "bumpbot running handlers does not show it" do
        send_command("bumpbot running handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          No command or event handlers are running right now.
        EOM
      end

      it "bumpbot handlers shows it" do
        send_command("bumpbot handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          handling command "test command" from Test User succeeded just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "GET /bumpbot/handlers/1/handler.log shows it" do
        response = http.get("/bumpbot/handlers/1/handler.log")
        expect(response.status).to eq(200)
        expect(strip_log_data(response.body)).to eq(strip_eom_block(<<-EOM))
          [DEBUG] Started handling command "test command" from Test User
          [     ] Completed handling command "test command" from Test User in 00:00:00
          [     ] Cleaned up sandbox directory /TMPDIR/cache/sandbox/1 after successful command ...
        EOM
      end
    end

    context "when a handler fails" do
      before do
        send_command("test command failed_miserably")
      end

      it "bumpbot running handlers does not show it" do
        send_command("bumpbot running handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed_miserably
          No command or event handlers are running right now.
        EOM
      end

      it "bumpbot handlers shows it" do
        send_command("bumpbot handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed_miserably
          handling command "test command failed_miserably" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "bumpbot handlers shows 2 seconds ago after 2 seconds have passed" do
        sleep(2)
        send_command("test command failed_just_now")
        send_command("bumpbot handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed_miserably
          **ERROR:** failed_just_now
          handling command "test command failed_just_now" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/2/handler.log|Log> <http://localhost:8080/bumpbot/handlers/2/sandbox.tgz|Download Sandbox>
          handling command "test command failed_miserably" from Test User failed 2 seconds ago after 00:00:00. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "GET /bumpbot/handlers/1/handler.log shows it" do
        response = http.get("/bumpbot/handlers/1/handler.log")
        expect(response.status).to eq(200)
        expect(strip_log_data(response.body)).to eq(strip_eom_block(<<-EOM))
          [DEBUG] Started handling command "test command failed_miserably" from Test User
          [ERROR] failed_miserably
          [DEBUG] Completed handling command "test command failed_miserably" from Test User in 00:00:00
        EOM
      end
    end

    context "when 15 handlers fail" do
      before do
        1.upto(15) do |i|
          send_command("test command failed#{i}")
        end
      end

      it "bumpbot handlers shows 1-10 by default" do
        send_command("bumpbot handlers")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed1
          **ERROR:** failed2
          **ERROR:** failed3
          **ERROR:** failed4
          **ERROR:** failed5
          **ERROR:** failed6
          **ERROR:** failed7
          **ERROR:** failed8
          **ERROR:** failed9
          **ERROR:** failed10
          **ERROR:** failed11
          **ERROR:** failed12
          **ERROR:** failed13
          **ERROR:** failed14
          **ERROR:** failed15
          handling command "test command failed15" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/15/handler.log|Log> <http://localhost:8080/bumpbot/handlers/15/sandbox.tgz|Download Sandbox>
          handling command "test command failed14" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/14/handler.log|Log> <http://localhost:8080/bumpbot/handlers/14/sandbox.tgz|Download Sandbox>
          handling command "test command failed13" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/13/handler.log|Log> <http://localhost:8080/bumpbot/handlers/13/sandbox.tgz|Download Sandbox>
          handling command "test command failed12" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/12/handler.log|Log> <http://localhost:8080/bumpbot/handlers/12/sandbox.tgz|Download Sandbox>
          handling command "test command failed11" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/11/handler.log|Log> <http://localhost:8080/bumpbot/handlers/11/sandbox.tgz|Download Sandbox>
          handling command "test command failed10" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/10/handler.log|Log> <http://localhost:8080/bumpbot/handlers/10/sandbox.tgz|Download Sandbox>
          handling command "test command failed9" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/9/handler.log|Log> <http://localhost:8080/bumpbot/handlers/9/sandbox.tgz|Download Sandbox>
          handling command "test command failed8" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/8/handler.log|Log> <http://localhost:8080/bumpbot/handlers/8/sandbox.tgz|Download Sandbox>
          handling command "test command failed7" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/7/handler.log|Log> <http://localhost:8080/bumpbot/handlers/7/sandbox.tgz|Download Sandbox>
          handling command "test command failed6" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/6/handler.log|Log> <http://localhost:8080/bumpbot/handlers/6/sandbox.tgz|Download Sandbox>
          This is only handlers 1-10 out of 15. To show the next 10, say "handlers 11-21".
        EOM
      end

      it "bumpbot handlers 1-15 shows all of them" do
        send_command("bumpbot handlers 1-15")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed1
          **ERROR:** failed2
          **ERROR:** failed3
          **ERROR:** failed4
          **ERROR:** failed5
          **ERROR:** failed6
          **ERROR:** failed7
          **ERROR:** failed8
          **ERROR:** failed9
          **ERROR:** failed10
          **ERROR:** failed11
          **ERROR:** failed12
          **ERROR:** failed13
          **ERROR:** failed14
          **ERROR:** failed15
          handling command "test command failed15" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/15/handler.log|Log> <http://localhost:8080/bumpbot/handlers/15/sandbox.tgz|Download Sandbox>
          handling command "test command failed14" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/14/handler.log|Log> <http://localhost:8080/bumpbot/handlers/14/sandbox.tgz|Download Sandbox>
          handling command "test command failed13" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/13/handler.log|Log> <http://localhost:8080/bumpbot/handlers/13/sandbox.tgz|Download Sandbox>
          handling command "test command failed12" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/12/handler.log|Log> <http://localhost:8080/bumpbot/handlers/12/sandbox.tgz|Download Sandbox>
          handling command "test command failed11" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/11/handler.log|Log> <http://localhost:8080/bumpbot/handlers/11/sandbox.tgz|Download Sandbox>
          handling command "test command failed10" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/10/handler.log|Log> <http://localhost:8080/bumpbot/handlers/10/sandbox.tgz|Download Sandbox>
          handling command "test command failed9" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/9/handler.log|Log> <http://localhost:8080/bumpbot/handlers/9/sandbox.tgz|Download Sandbox>
          handling command "test command failed8" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/8/handler.log|Log> <http://localhost:8080/bumpbot/handlers/8/sandbox.tgz|Download Sandbox>
          handling command "test command failed7" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/7/handler.log|Log> <http://localhost:8080/bumpbot/handlers/7/sandbox.tgz|Download Sandbox>
          handling command "test command failed6" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/6/handler.log|Log> <http://localhost:8080/bumpbot/handlers/6/sandbox.tgz|Download Sandbox>
          handling command "test command failed5" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log> <http://localhost:8080/bumpbot/handlers/5/sandbox.tgz|Download Sandbox>
          handling command "test command failed4" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/4/handler.log|Log> <http://localhost:8080/bumpbot/handlers/4/sandbox.tgz|Download Sandbox>
          handling command "test command failed3" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/3/handler.log|Log> <http://localhost:8080/bumpbot/handlers/3/sandbox.tgz|Download Sandbox>
          handling command "test command failed2" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/2/handler.log|Log> <http://localhost:8080/bumpbot/handlers/2/sandbox.tgz|Download Sandbox>
          handling command "test command failed1" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "bumpbot handlers 2- shows all but the first" do
        send_command("bumpbot handlers 2-")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed1
          **ERROR:** failed2
          **ERROR:** failed3
          **ERROR:** failed4
          **ERROR:** failed5
          **ERROR:** failed6
          **ERROR:** failed7
          **ERROR:** failed8
          **ERROR:** failed9
          **ERROR:** failed10
          **ERROR:** failed11
          **ERROR:** failed12
          **ERROR:** failed13
          **ERROR:** failed14
          **ERROR:** failed15
          handling command "test command failed14" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/14/handler.log|Log> <http://localhost:8080/bumpbot/handlers/14/sandbox.tgz|Download Sandbox>
          handling command "test command failed13" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/13/handler.log|Log> <http://localhost:8080/bumpbot/handlers/13/sandbox.tgz|Download Sandbox>
          handling command "test command failed12" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/12/handler.log|Log> <http://localhost:8080/bumpbot/handlers/12/sandbox.tgz|Download Sandbox>
          handling command "test command failed11" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/11/handler.log|Log> <http://localhost:8080/bumpbot/handlers/11/sandbox.tgz|Download Sandbox>
          handling command "test command failed10" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/10/handler.log|Log> <http://localhost:8080/bumpbot/handlers/10/sandbox.tgz|Download Sandbox>
          handling command "test command failed9" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/9/handler.log|Log> <http://localhost:8080/bumpbot/handlers/9/sandbox.tgz|Download Sandbox>
          handling command "test command failed8" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/8/handler.log|Log> <http://localhost:8080/bumpbot/handlers/8/sandbox.tgz|Download Sandbox>
          handling command "test command failed7" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/7/handler.log|Log> <http://localhost:8080/bumpbot/handlers/7/sandbox.tgz|Download Sandbox>
          handling command "test command failed6" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/6/handler.log|Log> <http://localhost:8080/bumpbot/handlers/6/sandbox.tgz|Download Sandbox>
          handling command "test command failed5" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log> <http://localhost:8080/bumpbot/handlers/5/sandbox.tgz|Download Sandbox>
          handling command "test command failed4" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/4/handler.log|Log> <http://localhost:8080/bumpbot/handlers/4/sandbox.tgz|Download Sandbox>
          handling command "test command failed3" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/3/handler.log|Log> <http://localhost:8080/bumpbot/handlers/3/sandbox.tgz|Download Sandbox>
          handling command "test command failed2" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/2/handler.log|Log> <http://localhost:8080/bumpbot/handlers/2/sandbox.tgz|Download Sandbox>
          handling command "test command failed1" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "bumpbot handlers 11-15 shows the last 5" do
        send_command("bumpbot handlers 11-15")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed1
          **ERROR:** failed2
          **ERROR:** failed3
          **ERROR:** failed4
          **ERROR:** failed5
          **ERROR:** failed6
          **ERROR:** failed7
          **ERROR:** failed8
          **ERROR:** failed9
          **ERROR:** failed10
          **ERROR:** failed11
          **ERROR:** failed12
          **ERROR:** failed13
          **ERROR:** failed14
          **ERROR:** failed15
          handling command "test command failed5" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log> <http://localhost:8080/bumpbot/handlers/5/sandbox.tgz|Download Sandbox>
          handling command "test command failed4" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/4/handler.log|Log> <http://localhost:8080/bumpbot/handlers/4/sandbox.tgz|Download Sandbox>
          handling command "test command failed3" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/3/handler.log|Log> <http://localhost:8080/bumpbot/handlers/3/sandbox.tgz|Download Sandbox>
          handling command "test command failed2" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/2/handler.log|Log> <http://localhost:8080/bumpbot/handlers/2/sandbox.tgz|Download Sandbox>
          handling command "test command failed1" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log> <http://localhost:8080/bumpbot/handlers/1/sandbox.tgz|Download Sandbox>
        EOM
      end

      it "bumpbot handlers 11 shows the 11th" do
        send_command("bumpbot handlers 11")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** failed1
          **ERROR:** failed2
          **ERROR:** failed3
          **ERROR:** failed4
          **ERROR:** failed5
          **ERROR:** failed6
          **ERROR:** failed7
          **ERROR:** failed8
          **ERROR:** failed9
          **ERROR:** failed10
          **ERROR:** failed11
          **ERROR:** failed12
          **ERROR:** failed13
          **ERROR:** failed14
          **ERROR:** failed15
          handling command "test command failed5" from Test User failed just now after 00:00:00. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log> <http://localhost:8080/bumpbot/handlers/5/sandbox.tgz|Download Sandbox>
          This is only handlers 11-11 out of 15. To show the next 10, say "handlers 12-22".
        EOM
      end
    end
  end
end
