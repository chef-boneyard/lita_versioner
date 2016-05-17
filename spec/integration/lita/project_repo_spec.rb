require "spec_helper"
require "tmpdir"
require "fileutils"

describe Lita::ProjectRepo, lita: true do

  let(:tmpdir) { Dir.mktmpdir }
  let(:project_name) { "lita-versioner" }
  let(:project_url) { "https://github.com/chef/#{project_name}.git" }
  let(:version_bump_cmd) { nil }
  let(:version_show_cmd) { nil }

  let(:robot) { Lita::Robot.new(registry) }
  let(:handler) do
    Lita::Handlers::BumpbotHandler.new(robot).tap do |h|
      h.project_name = project_name
      h.send(:init_event, "test")
    end
  end
  let(:project_repo) { Lita::ProjectRepo.new(handler) }

  before do
    registry.register_handler(Lita::Handlers::BumpbotHandler)
    registry.register_adapter(:test, Lita::Adapters::Test)
    registry.config.robot.adapter = :test
    registry.configure do |c|
      c.handlers.versioner.jenkins_username = "our_jenkins_user"
      c.handlers.versioner.jenkins_api_token = "our_jenkins_api_token"
      c.handlers.versioner.projects = {
        project_name => {
          pipeline: "our_pipeline",
          github_url: project_url,
          version_bump_command: version_bump_cmd,
          version_show_command: version_show_cmd,
          dependency_update_command: "",
          inform_channel: "our_channel",
        },
      }
    end

    @current_pwd = Dir.pwd
    Dir.chdir(tmpdir)
  end

  after do
    Dir.chdir(@current_pwd)
    FileUtils.rm_rf(tmpdir)
  end

  it "can clone the repo" do
    project_repo.refresh
    expect(Dir.exists?(project_repo.repo_directory)).to be true
    expect(Dir["#{project_repo.repo_directory}/**/*"].length).to be > 5
  end

  context "with an existing repo" do
    before do
      project_repo.refresh
      files = Dir["#{project_repo.repo_directory}/**/*"]
      @file_count = files.length

      # Delete some files
      files.first(5).each do |p|
        FileUtils.rm_rf(p)
      end
    end

    it "can update the repo" do
      project_repo.refresh
      expect(Dir.exists?(project_repo.repo_directory)).to be true
      expect(Dir["#{project_repo.repo_directory}/**/*"].length).to eq(@file_count)
    end
  end

  context "with setup to bump the version" do
    let(:version_bump_cmd) { "echo 1.1.1 > VERSION" }
    let(:version_show_cmd) { "echo 1.1.1" }
    let(:version_file) { File.join(project_repo.repo_directory, "VERSION") }
    before do
      original_run_command = project_repo.method(:run_command)
      allow(project_repo).to receive(:run_command) do |command|
        # Do not push the branch for real. But run a status command to be able
        # correctly return a Shellout object.
        if command == "git push origin master --tags"
          command = "git status"
        end
        original_run_command.call(command)
      end

      FileUtils.mkdir_p(project_repo.repo_directory)
      FileUtils.touch(version_file)
      File.open(version_file, "w+") do |f|
        f.puts "1.1.0"
      end
      project_repo.run_command("git init .")
    end

    it "can bump the version" do
      project_repo.bump_version
      project_repo.tag_and_commit
      expect(File.read(version_file)).to match /1.1.1/
      expect(project_repo.run_command("git log").stdout).to match /Bump version of lita-versioner/
      expect(project_repo.run_command("git describe --tags").stdout.chomp).to eq("v1.1.1")
    end
  end

end
