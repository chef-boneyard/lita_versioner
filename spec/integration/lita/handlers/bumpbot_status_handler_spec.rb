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

  # Allow things to take 1 second extra and still match
  def one_second_slop(log)
    log.gsub("after 1 second", "after 0 seconds")
  end

  with_jenkins_server "http://manhattan.ci.chef.co"

  context "bumpbot handlers" do
    it "bumpbot running handlers with arguments emits a reasonable error message" do
      send_command("bumpbot running handlers blarghle")

      expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
        Too many arguments (1 for 0)!
        Usage: bumpbot running handlers   - Get the list of running handlers in bumpbot
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    it "bumpbot handlers with more than one argument emits a reasonable error message" do
      send_command("bumpbot handlers 1-2 blarghle")

      expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
        Too many arguments (2 for 1)!
        Usage: bumpbot handlers [RANGE]   - Get the list of running and failed handlers in bumpbot (corresponds to the list of failed commands). Optional RANGE will get you a list of handlers. Default range is 1-10.
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    context "when there are no running handlers" do
      it "bumpbot running handlers reports no handlers" do
        send_command("bumpbot running handlers")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          No command or event handlers are running right now.
        EOM
      end

      it "bumpbot handlers reports no handlers" do
        send_command("bumpbot handlers")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
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

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          Running `test wait` for @Test User
        EOM
      end

      it "bumpbot handlers shows it" do
        send_command("bumpbot handlers")

        handler.stop
        handler_thread.join

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          Running `test wait` for @Test User in progress. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log>
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
          [DEBUG] Started Running `test wait` for @Test User
          [     ] Completed Running `test wait` for @Test User in 0 seconds
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

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          No command or event handlers are running right now.
        EOM
      end

      it "bumpbot handlers shows it" do
        send_command("bumpbot handlers")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          Running `test command` for @Test User succeeded after 0 seconds. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log>
        EOM
      end

      it "GET /bumpbot/handlers/1/handler.log shows it" do
        response = http.get("/bumpbot/handlers/1/handler.log")
        expect(response.status).to eq(200)
        expect(strip_log_data(response.body)).to eq(strip_eom_block(<<-EOM))
          [DEBUG] Started Running `test command` for @Test User
          [     ] Completed Running `test command` for @Test User in 0 seconds
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

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          failed_miserably
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
          No command or event handlers are running right now.
        EOM
      end

      it "bumpbot handlers shows it" do
        send_command("bumpbot handlers")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          failed_miserably
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
          Running `test command failed_miserably` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log>
        EOM
      end

      it "GET /bumpbot/handlers/1/handler.log shows it" do
        response = http.get("/bumpbot/handlers/1/handler.log")
        expect(response.status).to eq(200)
        expect(strip_log_data(response.body)).to eq(strip_eom_block(<<-EOM))
          [DEBUG] Started Running `test command failed_miserably` for @Test User
          [ERROR] failed_miserably
          [DEBUG] Completed Running `test command failed_miserably` for @Test User in 0 seconds
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

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          failed1
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
          failed2
          Failed. <http://localhost:8080/bumpbot/handlers/2/handler.log|Full log available here.>
          failed3
          Failed. <http://localhost:8080/bumpbot/handlers/3/handler.log|Full log available here.>
          failed4
          Failed. <http://localhost:8080/bumpbot/handlers/4/handler.log|Full log available here.>
          failed5
          Failed. <http://localhost:8080/bumpbot/handlers/5/handler.log|Full log available here.>
          failed6
          Failed. <http://localhost:8080/bumpbot/handlers/6/handler.log|Full log available here.>
          failed7
          Failed. <http://localhost:8080/bumpbot/handlers/7/handler.log|Full log available here.>
          failed8
          Failed. <http://localhost:8080/bumpbot/handlers/8/handler.log|Full log available here.>
          failed9
          Failed. <http://localhost:8080/bumpbot/handlers/9/handler.log|Full log available here.>
          failed10
          Failed. <http://localhost:8080/bumpbot/handlers/10/handler.log|Full log available here.>
          failed11
          Failed. <http://localhost:8080/bumpbot/handlers/11/handler.log|Full log available here.>
          failed12
          Failed. <http://localhost:8080/bumpbot/handlers/12/handler.log|Full log available here.>
          failed13
          Failed. <http://localhost:8080/bumpbot/handlers/13/handler.log|Full log available here.>
          failed14
          Failed. <http://localhost:8080/bumpbot/handlers/14/handler.log|Full log available here.>
          failed15
          Failed. <http://localhost:8080/bumpbot/handlers/15/handler.log|Full log available here.>
          Running `test command failed15` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/15/handler.log|Log>
          Running `test command failed14` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/14/handler.log|Log>
          Running `test command failed13` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/13/handler.log|Log>
          Running `test command failed12` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/12/handler.log|Log>
          Running `test command failed11` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/11/handler.log|Log>
          Running `test command failed10` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/10/handler.log|Log>
          Running `test command failed9` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/9/handler.log|Log>
          Running `test command failed8` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/8/handler.log|Log>
          Running `test command failed7` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/7/handler.log|Log>
          Running `test command failed6` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/6/handler.log|Log>
          1-10 of 15, recent first. For more, say `handlers 11-21`.
        EOM
      end

      it "bumpbot handlers 1-15 shows all of them" do
        send_command("bumpbot handlers 1-15")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          failed1
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
          failed2
          Failed. <http://localhost:8080/bumpbot/handlers/2/handler.log|Full log available here.>
          failed3
          Failed. <http://localhost:8080/bumpbot/handlers/3/handler.log|Full log available here.>
          failed4
          Failed. <http://localhost:8080/bumpbot/handlers/4/handler.log|Full log available here.>
          failed5
          Failed. <http://localhost:8080/bumpbot/handlers/5/handler.log|Full log available here.>
          failed6
          Failed. <http://localhost:8080/bumpbot/handlers/6/handler.log|Full log available here.>
          failed7
          Failed. <http://localhost:8080/bumpbot/handlers/7/handler.log|Full log available here.>
          failed8
          Failed. <http://localhost:8080/bumpbot/handlers/8/handler.log|Full log available here.>
          failed9
          Failed. <http://localhost:8080/bumpbot/handlers/9/handler.log|Full log available here.>
          failed10
          Failed. <http://localhost:8080/bumpbot/handlers/10/handler.log|Full log available here.>
          failed11
          Failed. <http://localhost:8080/bumpbot/handlers/11/handler.log|Full log available here.>
          failed12
          Failed. <http://localhost:8080/bumpbot/handlers/12/handler.log|Full log available here.>
          failed13
          Failed. <http://localhost:8080/bumpbot/handlers/13/handler.log|Full log available here.>
          failed14
          Failed. <http://localhost:8080/bumpbot/handlers/14/handler.log|Full log available here.>
          failed15
          Failed. <http://localhost:8080/bumpbot/handlers/15/handler.log|Full log available here.>
          Running `test command failed15` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/15/handler.log|Log>
          Running `test command failed14` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/14/handler.log|Log>
          Running `test command failed13` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/13/handler.log|Log>
          Running `test command failed12` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/12/handler.log|Log>
          Running `test command failed11` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/11/handler.log|Log>
          Running `test command failed10` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/10/handler.log|Log>
          Running `test command failed9` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/9/handler.log|Log>
          Running `test command failed8` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/8/handler.log|Log>
          Running `test command failed7` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/7/handler.log|Log>
          Running `test command failed6` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/6/handler.log|Log>
          Running `test command failed5` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log>
          Running `test command failed4` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/4/handler.log|Log>
          Running `test command failed3` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/3/handler.log|Log>
          Running `test command failed2` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/2/handler.log|Log>
          Running `test command failed1` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log>
        EOM
      end

      it "bumpbot handlers 2- shows all but the first" do
        send_command("bumpbot handlers 2-")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          failed1
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
          failed2
          Failed. <http://localhost:8080/bumpbot/handlers/2/handler.log|Full log available here.>
          failed3
          Failed. <http://localhost:8080/bumpbot/handlers/3/handler.log|Full log available here.>
          failed4
          Failed. <http://localhost:8080/bumpbot/handlers/4/handler.log|Full log available here.>
          failed5
          Failed. <http://localhost:8080/bumpbot/handlers/5/handler.log|Full log available here.>
          failed6
          Failed. <http://localhost:8080/bumpbot/handlers/6/handler.log|Full log available here.>
          failed7
          Failed. <http://localhost:8080/bumpbot/handlers/7/handler.log|Full log available here.>
          failed8
          Failed. <http://localhost:8080/bumpbot/handlers/8/handler.log|Full log available here.>
          failed9
          Failed. <http://localhost:8080/bumpbot/handlers/9/handler.log|Full log available here.>
          failed10
          Failed. <http://localhost:8080/bumpbot/handlers/10/handler.log|Full log available here.>
          failed11
          Failed. <http://localhost:8080/bumpbot/handlers/11/handler.log|Full log available here.>
          failed12
          Failed. <http://localhost:8080/bumpbot/handlers/12/handler.log|Full log available here.>
          failed13
          Failed. <http://localhost:8080/bumpbot/handlers/13/handler.log|Full log available here.>
          failed14
          Failed. <http://localhost:8080/bumpbot/handlers/14/handler.log|Full log available here.>
          failed15
          Failed. <http://localhost:8080/bumpbot/handlers/15/handler.log|Full log available here.>
          Running `test command failed14` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/14/handler.log|Log>
          Running `test command failed13` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/13/handler.log|Log>
          Running `test command failed12` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/12/handler.log|Log>
          Running `test command failed11` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/11/handler.log|Log>
          Running `test command failed10` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/10/handler.log|Log>
          Running `test command failed9` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/9/handler.log|Log>
          Running `test command failed8` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/8/handler.log|Log>
          Running `test command failed7` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/7/handler.log|Log>
          Running `test command failed6` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/6/handler.log|Log>
          Running `test command failed5` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log>
          Running `test command failed4` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/4/handler.log|Log>
          Running `test command failed3` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/3/handler.log|Log>
          Running `test command failed2` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/2/handler.log|Log>
          Running `test command failed1` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log>
        EOM
      end

      it "bumpbot handlers 11-15 shows the last 5" do
        send_command("bumpbot handlers 11-15")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          failed1
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
          failed2
          Failed. <http://localhost:8080/bumpbot/handlers/2/handler.log|Full log available here.>
          failed3
          Failed. <http://localhost:8080/bumpbot/handlers/3/handler.log|Full log available here.>
          failed4
          Failed. <http://localhost:8080/bumpbot/handlers/4/handler.log|Full log available here.>
          failed5
          Failed. <http://localhost:8080/bumpbot/handlers/5/handler.log|Full log available here.>
          failed6
          Failed. <http://localhost:8080/bumpbot/handlers/6/handler.log|Full log available here.>
          failed7
          Failed. <http://localhost:8080/bumpbot/handlers/7/handler.log|Full log available here.>
          failed8
          Failed. <http://localhost:8080/bumpbot/handlers/8/handler.log|Full log available here.>
          failed9
          Failed. <http://localhost:8080/bumpbot/handlers/9/handler.log|Full log available here.>
          failed10
          Failed. <http://localhost:8080/bumpbot/handlers/10/handler.log|Full log available here.>
          failed11
          Failed. <http://localhost:8080/bumpbot/handlers/11/handler.log|Full log available here.>
          failed12
          Failed. <http://localhost:8080/bumpbot/handlers/12/handler.log|Full log available here.>
          failed13
          Failed. <http://localhost:8080/bumpbot/handlers/13/handler.log|Full log available here.>
          failed14
          Failed. <http://localhost:8080/bumpbot/handlers/14/handler.log|Full log available here.>
          failed15
          Failed. <http://localhost:8080/bumpbot/handlers/15/handler.log|Full log available here.>
          Running `test command failed5` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log>
          Running `test command failed4` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/4/handler.log|Log>
          Running `test command failed3` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/3/handler.log|Log>
          Running `test command failed2` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/2/handler.log|Log>
          Running `test command failed1` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/1/handler.log|Log>
        EOM
      end

      it "bumpbot handlers 11 shows the 11th" do
        send_command("bumpbot handlers 11")

        expect(one_second_slop(reply_string)).to eq(strip_eom_block(<<-EOM))
          failed1
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
          failed2
          Failed. <http://localhost:8080/bumpbot/handlers/2/handler.log|Full log available here.>
          failed3
          Failed. <http://localhost:8080/bumpbot/handlers/3/handler.log|Full log available here.>
          failed4
          Failed. <http://localhost:8080/bumpbot/handlers/4/handler.log|Full log available here.>
          failed5
          Failed. <http://localhost:8080/bumpbot/handlers/5/handler.log|Full log available here.>
          failed6
          Failed. <http://localhost:8080/bumpbot/handlers/6/handler.log|Full log available here.>
          failed7
          Failed. <http://localhost:8080/bumpbot/handlers/7/handler.log|Full log available here.>
          failed8
          Failed. <http://localhost:8080/bumpbot/handlers/8/handler.log|Full log available here.>
          failed9
          Failed. <http://localhost:8080/bumpbot/handlers/9/handler.log|Full log available here.>
          failed10
          Failed. <http://localhost:8080/bumpbot/handlers/10/handler.log|Full log available here.>
          failed11
          Failed. <http://localhost:8080/bumpbot/handlers/11/handler.log|Full log available here.>
          failed12
          Failed. <http://localhost:8080/bumpbot/handlers/12/handler.log|Full log available here.>
          failed13
          Failed. <http://localhost:8080/bumpbot/handlers/13/handler.log|Full log available here.>
          failed14
          Failed. <http://localhost:8080/bumpbot/handlers/14/handler.log|Full log available here.>
          failed15
          Failed. <http://localhost:8080/bumpbot/handlers/15/handler.log|Full log available here.>
          Running `test command failed5` for @Test User failed after 0 seconds. <http://localhost:8080/bumpbot/handlers/5/handler.log|Log>
          11-11 of 15, recent first. For more, say `handlers 12-22`.
        EOM
      end
    end
  end
end
