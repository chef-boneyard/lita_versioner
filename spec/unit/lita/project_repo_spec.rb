require "spec_helper"
require "lita/project_repo"

RSpec.describe Lita::ProjectRepo do

  let(:git_url) { "git@github.com:chef/omnibus-harmony.git" }

  let(:version_show_command) { "bundle exec rake version:show" }

  let(:version_bump_command) { "bundle install && bundle exec rake version:bump_patch" }

  let(:project_options) do
    {
      github_url: git_url,
      version_show_command: version_show_command,
      version_bump_command: version_bump_command,
    }
  end

  let(:logger) do
    double("Logger").tap do |l|
      allow(l).to receive(:info)
    end
  end

  subject(:project_repo) do
    described_class.new(project_options)
  end

  before do
    allow(Lita).to receive(:logger).and_return(logger)
  end

  it "has a project repo" do
    expect(project_repo.github_url).to eq(git_url)
  end

  it "has a version display command" do
    expect(project_repo.version_show_command).to eq(version_show_command)
  end

  it "has a version bump command" do
    expect(project_repo.version_bump_command).to eq(version_bump_command)
  end

  it "computes the repo name from the git URL" do
    expect(project_repo.repo_name).to eq("omnibus-harmony")
  end

  it "computes the repo directory from the name" do
    expect(project_repo.repo_directory).to eq("./cache/omnibus-harmony")
  end

  describe "refresh" do

    before do
      allow(File).to receive(:exist?).and_return(false)
      expect(Dir).to receive(:mkdir).with("./cache")

      x = double("Please stub calls to Mixlib::ShellOut.new with exact arguments")
      allow(Mixlib::ShellOut).to receive(:new).and_return(x)
    end

    context "when the repo isn't cloned" do

      let(:clone_shellout) { double("Mixlib::ShellOut", error?: false) }

      it "clones the repo" do
        expect(Mixlib::ShellOut).to receive(:new).
          with("git clone git@github.com:chef/omnibus-harmony.git", cwd: "./cache", timeout: 3600).
          and_return(clone_shellout)
        expect(clone_shellout).to receive(:run_command)
        project_repo.refresh
      end

    end

    context "when the repo is cloned" do

      let(:fetch_shellout) { double("Mixlib::ShellOut", error?: false) }
      let(:reset_shellout) { double("Mixlib::ShellOut", error?: false) }
      let(:clean_shellout) { double("Mixlib::ShellOut", error?: false) }

      before do
        allow(Dir).to receive(:exists?).with(project_repo.repo_directory).and_return(true)
      end

      it "fetches updates, cleans and resets to the current master" do
        expect(Mixlib::ShellOut).to receive(:new).
          with("git fetch origin", cwd: "./cache/omnibus-harmony", timeout: 3600).
          and_return(fetch_shellout)
        expect(fetch_shellout).to receive(:run_command)

        expect(Mixlib::ShellOut).to receive(:new).
          with("git reset --hard origin/master", cwd: "./cache/omnibus-harmony", timeout: 3600).
          and_return(fetch_shellout)
        expect(fetch_shellout).to receive(:run_command)

        expect(Mixlib::ShellOut).to receive(:new).
          with("git clean -fdx", cwd: "./cache/omnibus-harmony", timeout: 3600).
          and_return(clean_shellout)
        expect(clean_shellout).to receive(:run_command)

        project_repo.refresh
      end

    end

  end

  describe "bump version" do

    let(:bump_shellout) { double("Mixlib::ShellOut", error?: false) }

    before do
      x = double("Please stub calls to Mixlib::ShellOut.new with exact arguments")
      allow(Mixlib::ShellOut).to receive(:new).and_return(x)
    end

    it "runs the version bump command" do
      expect(Mixlib::ShellOut).to receive(:new).
        with(version_bump_command, cwd: "./cache/omnibus-harmony", timeout: 3600).
        and_return(bump_shellout)
      expect(bump_shellout).to receive(:run_command)

      project_repo.bump_version
    end
  end

  describe "tag and commit" do

    let(:version) { "12.34.56\n" }

    let(:config_email_shellout) { double("Mixlib::ShellOut", error?: false) }
    let(:config_user_shellout) { double("Mixlib::ShellOut", error?: false) }
    let(:git_add_shellout) { double("Mixlib::ShellOut", error?: false) }
    let(:git_commit_shellout) { double("Mixlib::ShellOut", error?: false) }
    let(:git_tag_shellout) { double("Mixlib::ShellOut", error?: false) }
    let(:git_push_shellout) { double("Mixlib::ShellOut", error?: false) }

    let(:config_check_shellout) { double("Mixlib::ShellOut", error?: false, stdout: "") }
    let(:version_read_shellout) { double("Mixlib::ShellOut", error?: false, stdout: version) }

    it "configures committer info, commits, tags and pushes" do
      [
        [ "git config -l", config_check_shellout ],
        [ "git config user.email \"chef-versioner@chef.io\"", config_email_shellout ],
        [ "git config user.name \"Chef Versioner\"", config_user_shellout ],
        [ "git add -A", git_add_shellout ],
        [ "git commit -m \"Bump version of omnibus-harmony to 12.34.56 by Chef Versioner.\"", git_commit_shellout ],
        [ version_show_command, version_read_shellout ],
        [ "git tag -a v12.34.56 -m \"Version tag for 12.34.56.\"", git_tag_shellout ],
        [ "git push origin master --tags", git_push_shellout ],
      ].each do |command_string, shellout_object|
        expect(Mixlib::ShellOut).to receive(:new).
          with(command_string, cwd: "./cache/omnibus-harmony", timeout: 3600).
          and_return(shellout_object)
        expect(shellout_object).to receive(:run_command)
      end

      project_repo.tag_and_commit
    end
  end

end
