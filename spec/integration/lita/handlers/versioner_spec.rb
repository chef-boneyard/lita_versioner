require "spec_helper"
require "tmpdir"
require "fileutils"

describe Lita::Handlers::Versioner, lita_handler: true, additional_lita_handlers: Lita::Handlers::BumpbotHandler do
  let(:config) { Lita.config.handlers.versioner }
  let(:git_remote) { File.join(tmpdir, "lita-test") }

  # Create a notifications room to receive notifications from event handlers
  let(:notifications_room) { Lita::Room.create_or_update("#notifications") }
  before do
    allow_any_instance_of(Lita::Handlers::BumpbotHandler).to receive(:source_by_name) { |name| notifications_room }
  end

  # Create a repository with file.txt = A, deps.txt=X
  attr_reader :initial_commit_sha
  before do
    create_remote_git_repo(git_remote, "a.txt" => "A", "file.txt" => "A", "deps.txt" => "X")
    @initial_commit_sha = git_sha(git_remote, ref: "master")
  end

  def reply_lines
    replies.flat_map { |r| r.lines }.map { |l| l.chomp }
  end

  def reply_string
    reply_lines.map { |l| "#{l}\n" }.join("")
  end

  #
  # Give us a jenkins_http we can expect http messages from
  #
  let(:jenkins_http) { double("jenkins_http") }
  before do
    allow(LitaVersioner::JenkinsHTTP).to receive(:new).
      with(base_uri: "http://manhattan.ci.chef.co/", username: "ci", api_token: "ci_api_token").
      and_return(jenkins_http)
  end

  # Configure the bot
  before do
    config.jenkins_username = "ci"
    config.jenkins_api_token = "ci_api_token"
    config.trigger_real_builds = true
    config.cache_directory = File.join(tmpdir, "cache")
    config.sandbox_directory = File.join(config.cache_directory, "sandbox")
    config.debug_lines_in_pm = false
    config.default_inform_channel = "default_notifications"
    config.projects = {
      "lita-test" => {
        pipeline: "lita-test-trigger-release",
        github_url: git_remote,
        version_bump_command: "cat a.txt >> file.txt",
        version_show_command: "cat file.txt",
        dependency_update_command: "echo Y > deps.txt",
        inform_channel: "notifications",
      },
    }
  end

  # We override route() - therefore, the matcher doesn't work correctly.
  #it { is_expected.to route_command("build lita-test").to(:build) }
  it { is_expected.to route_http(:post, "/github_handler").to(:github_handler) }

  context "build" do

    it "build with no arguments emits a reasonable error message" do
      send_command("build")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        **ERROR:** No project specified!
        Usage: build PROJECT [GIT_REF]   - Kicks off a build for PROJECT with GIT_REF. GIT_REF default: master.
      EOM
    end

    it "build blarghle emits a reasonable error message" do
      send_command("build blarghle")
      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        **ERROR:** Invalid project. Valid projects: lita-test.
        Usage: build PROJECT [GIT_REF]   - Kicks off a build for PROJECT with GIT_REF. GIT_REF default: master.
      EOM
    end

    it "build lita-test master blarghle does not build (too many arguments)" do
      send_command("build lita-test master blarghle")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        **ERROR:** Too many arguments (3 for 2)!
        Usage: build PROJECT [GIT_REF]   - Kicks off a build for PROJECT with GIT_REF. GIT_REF default: master.
      EOM
    end

    it "build lita-test builds master" do
      expect(jenkins_http).to receive(:post).with(
        "/job/lita-test-trigger-release/buildWithParameters",
        { "GIT_REF" => "master", "EXPIRE_CACHE" => false, "INITIATED_BY" => "Test User" })

      send_command("build lita-test")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        Kicked off a build for 'lita-test-trigger-release' at ref 'master'.
      EOM
    end

    it "build lita-test example builds with the specified tag" do
      expect(jenkins_http).to receive(:post).with(
        "/job/lita-test-trigger-ad_hoc/buildWithParameters",
        { "GIT_REF" => "example", "EXPIRE_CACHE" => false, "INITIATED_BY" => "Test User" })

      send_command("build lita-test example")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        Kicked off a build for 'lita-test-trigger-ad_hoc' at ref 'example'.
      EOM
    end
  end

  context "bump" do
    it "build with no arguments emits a reasonable error message" do
      send_command("bump")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        **ERROR:** No project specified!
        Usage: bump PROJECT   - Bumps the version of PROJECT and starts a build.
      EOM
    end

    it "build blarghle emits a reasonable error message" do
      send_command("bump blarghle")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        **ERROR:** Invalid project. Valid projects: lita-test.
        Usage: bump PROJECT   - Bumps the version of PROJECT and starts a build.
      EOM
    end

    it "bump lita-test blarghle does not bump (too many arguments)" do
      send_command("bump lita-test blarghle")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        **ERROR:** Too many arguments (2 for 1)!
        Usage: bump PROJECT   - Bumps the version of PROJECT and starts a build.
      EOM
    end

    it "bump lita-test bumps the version of lita-test" do
      expect(jenkins_http).to receive(:post).with(
        "/job/lita-test-trigger-release/buildWithParameters",
        { "GIT_REF" => "vAA", "EXPIRE_CACHE" => false, "INITIATED_BY" => "Test User" })

      send_command("bump lita-test")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        Bumped version to AA
        Kicked off release build for 'lita-test-trigger-release' at ref 'vAA'.
      EOM

      expect(git_file(git_remote, "file.txt")).to eq("AA")
    end

    # TODO avoid this situation!!
    # Disabled this test because it fails intermittently (it's a race test)
    # it "two bump lita-tests at once triggers two builds but only one actual bump" do
    #   expect(jenkins_http).to receive(:post).with(
    #     "/job/lita-test-trigger-release/buildWithParameters",
    #     {"GIT_REF"=>"vAA", "EXPIRE_CACHE"=>false, "INITIATED_BY"=>"Test User"}).twice
    #
    #   t = Thread.new do
    #     send_command("bump lita-test")
    #   end
    #   send_command("bump lita-test")
    #   t.join
    #
    #   expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
    #     Bumped version to AA
    #     Kicked off release build for 'lita-test-trigger-release' at ref 'vAA'.
    #     Bumped version to AA
    #     Kicked off release build for 'lita-test-trigger-release' at ref 'vAA'.
    #   EOM
    #
    #   expect(git_file(git_remote, "file.txt")).to eq("AA")
    # end

    # it "when a commit comes in after the bump command is received, the bump command fails to push" do
    #   expect(jenkins_http).to receive(:post).with(
    #     "/job/lita-test-trigger-release/buildWithParameters",
    #     {"GIT_REF"=>"vAA", "EXPIRE_CACHE"=>false, "INITIATED_BY"=>"Test User"})
    #   send_command("bump lita-test")
    #   create_commit(git_remote, "file.txt")
    # end

    it "bump lita-test followed by bump lita-test bumps the version from subsequent SHAs" do
      expect(jenkins_http).to receive(:post).with(
        "/job/lita-test-trigger-release/buildWithParameters",
        { "GIT_REF" => "vAA", "EXPIRE_CACHE" => false, "INITIATED_BY" => "Test User" })
      send_command("bump lita-test")

      expect(git_file(git_remote, "file.txt")).to eq("AA")

      expect(jenkins_http).to receive(:post).with(
        "/job/lita-test-trigger-release/buildWithParameters",
        { "GIT_REF" => "vAAA", "EXPIRE_CACHE" => false, "INITIATED_BY" => "Test User" })

      send_command("bump lita-test")

      expect(reply_string).to eq(<<-EOM.gsub!(/^        /, ""))
        Bumped version to AA
        Kicked off release build for 'lita-test-trigger-release' at ref 'vAA'.
        Bumped version to AAA
        Kicked off release build for 'lita-test-trigger-release' at ref 'vAAA'.
      EOM

      expect(git_file(git_remote, "file.txt")).to eq("AAA")
    end
  end

  context "github handler" do
    def post_github_event(event_type, repository, pull_request_action, pull_request_merged, sha: initial_commit_sha, pull_number: 1)
      http.post "/github_handler" do |req|
        req.headers["X-GitHub-Event"] = event_type
        req.params[:payload] = {
          repository: {
            name: repository,
          },
          action: pull_request_action,
          pull_request: {
            merged: pull_request_merged,
            url: "https://api.github.com/repos/chef/#{repository}/pulls/#{pull_number}",
            html_url: "https://github.com/chef/#{repository}/pulls/#{pull_number}",
            merge_commit_sha: sha,
          },
        }.to_json
      end
    end

    context "for events other than pull-request" do
      it "skips build" do
        response = post_github_event("issues", "lita-test", "closed", false)
        expect(response.status).to eq(200)

        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(replies).to be_empty
        expect(response.body).to eq(reply_string)
      end
    end

    context "for unsupported projects" do
      it "skips build" do
        response = post_github_event("pull_request", "blarghle", "closed", true)
        expect(response.status).to eq(500)
        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(reply_string).to eq(<<-EOM.gsub!(/^          /, ""))
          **ERROR:** Repository 'blarghle' is not monitored by versioner!
        EOM
      end
    end

    context "for non-closed merges" do
      it "skips build" do
        response = post_github_event("pull_request", "lita-test", "opened", true)
        expect(response.status).to eq(200)
        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(response.body.strip).to eq("")
        expect(replies).to be_empty
      end
    end

    context "for pull-request events without merge" do
      it "skips build" do
        response = post_github_event("pull_request", "lita-test", "closed", false)
        expect(response.status).to eq(200)
        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(reply_string).to eq(<<-EOM.gsub!(/^          /, ""))
          Skipping: 'https://github.com/chef/lita-test/pulls/1'. It was closed without merging any commits.
        EOM
        expect(response.body).to eq(reply_string)
      end
    end

    context "for merged pull-requests" do
      it "bumps version and runs the build" do
        sha = create_commit(git_remote, "file.txt" => "Z")

        expect(jenkins_http).to receive(:post).with(
          "/job/lita-test-trigger-release/buildWithParameters",
          { "GIT_REF" => "vZA", "EXPIRE_CACHE" => false, "INITIATED_BY" => "BumpBot" })

        response = post_github_event("pull_request", "lita-test", "closed", true, sha: sha)
        expect(response.status).to eq(200)

        expect(git_file(git_remote, "file.txt")).to eq("ZA")

        expect(reply_string).to eq(<<-EOM.gsub!(/^          /, ""))
          'https://github.com/chef/lita-test/pulls/1' was just merged. Bumping version and submitting a build ...
          Bumped version to ZA
          Kicked off release build for 'lita-test-trigger-release' at ref 'vZA'.
        EOM
        expect(response.body).to eq(reply_string)
      end

      it "when another commit has been created before the merge is triggered, it fails to push but then handles the next merge" do
        sha1 = create_commit(git_remote, "file.txt" => "Z")
        sha2 = create_commit(git_remote, "file.txt" => "ZZ")

        response = post_github_event("pull_request", "lita-test", "closed", true, sha: sha1)
        expect(response.status).to eq(200)
        expect(response.body.strip).to eq("WARN: Skipping: 'https://github.com/chef/lita-test/pulls/1'. Latest master is at SHA 5a6d2b42c1d26c11616a4c07eb44ead0483661ae, but the pull request merged SHA 23da147c3c4244d787a02e792d7649c6b5ad7acd")

        expect(git_file(git_remote, "file.txt")).to eq("ZZ")

        expect(jenkins_http).to receive(:post).with(
          "/job/lita-test-trigger-release/buildWithParameters",
          { "GIT_REF" => "vZZA", "EXPIRE_CACHE" => false, "INITIATED_BY" => "BumpBot" })

        response2 = post_github_event("pull_request", "lita-test", "closed", true, sha: sha2, pull_number: 2)
        expect(response2.status).to eq(200)

        expect(git_file(git_remote, "file.txt")).to eq("ZZA")
        expect(response2.body).to eq(<<-EOM.gsub!(/^          /, ""))
          'https://github.com/chef/lita-test/pulls/2' was just merged. Bumping version and submitting a build ...
          Bumped version to ZZA
          Kicked off release build for 'lita-test-trigger-release' at ref 'vZZA'.
        EOM

        expect(reply_string).to eq("#{response.body}#{response2.body}")
      end
    end
  end
end
