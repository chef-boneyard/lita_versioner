require "spec_helper"
require "lita/project_repo"

RSpec.describe Lita::ProjectRepo do

  let(:git_url) { "git@github.com:chef/omnibus-harmony.git" }

  let(:version_show_command) { "bundle exec rake version:show" }

  let(:version_bump_command) { "bundle install && bundle exec rake version:bump_patch" }

  let(:dependency_update_command) { "bundle install && bundle exec rake dependencies" }

  let(:project_options) do
    {
      github_url: git_url,
      version_show_command: version_show_command,
      version_bump_command: version_bump_command,
      dependency_update_command: dependency_update_command,
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

  describe "update dependencies" do

    let(:dep_update_shellout) { double("Mixlib::ShellOut", error?: false) }

    it "runs the version bump command" do
      expect(Mixlib::ShellOut).to receive(:new).
        with(dependency_update_command, cwd: "./cache/omnibus-harmony", timeout: 3600).
        and_return(dep_update_shellout)
      expect(dep_update_shellout).to receive(:run_command)

      project_repo.update_dependencies
    end
  end

  describe "bump version" do

    let(:bump_shellout) { double("Mixlib::ShellOut", error?: false) }

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

  describe "checking for changes" do

    let(:diff_index_shellout) { double("Mixlib::ShellOut", error?: false, stdout: diff_index_output) }

    let(:diff_target) { "HEAD" }

    before do
      expect(Mixlib::ShellOut).to receive(:new).
             with("git diff-index --name-only #{diff_target}", cwd: "./cache/omnibus-harmony", timeout: 3600).
             and_return(diff_index_shellout)
      expect(diff_index_shellout).to receive(:run_command)
    end

    context "when there are no changes" do

      let(:diff_index_output) { "\n" }

      it "queries git for changes" do
        expect(project_repo.has_modified_files?).to be(false)
      end

    end

    context "where there are changes" do

      let(:diff_index_output) { "Gemfile.lock\n" }

      it "queries git for changes" do
        expect(project_repo.has_modified_files?).to be(true)
      end

    end

    describe "compared against a specific branch" do

      let(:diff_index_output) { "Gemfile.lock\n" }

      let(:diff_target) { "auto_dependency_bump_test" }

      it "queries git for changes" do
        expect(project_repo.has_modified_files?(diff_target)).to be(true)
      end

    end

  end

  describe "has file?" do

    let(:file_path_from_repo_root) { ".disable_dependency_updates" }

    context "when the file exists" do

      before do
        allow(File).to receive(:exist?).
          with("./cache/omnibus-harmony/.disable_dependency_updates").
          and_return(true)
      end

      it "returns true" do
        expect(project_repo.has_file?(file_path_from_repo_root)).to be(true)
      end

    end

    context "when the file doesn't exist" do

      before do
        allow(File).to receive(:exist?).
          with("./cache/omnibus-harmony/.disable_dependency_updates").
          and_return(false)
      end

      it "returns false" do
        expect(project_repo.has_file?(file_path_from_repo_root)).to be(false)
      end

    end

  end

  describe "branch exists?" do

    before do
      expect(Mixlib::ShellOut).to receive(:new).
        with("git rev-parse --verify auto_dependency_bump_test", cwd: "./cache/omnibus-harmony", timeout: 3600).
        and_return(git_rev_parse_shellout)
      expect(git_rev_parse_shellout).to receive(:run_command)
    end

    context "when the branch exists" do

      let(:git_rev_parse_shellout) { double("Mixlib::ShellOut", error?: false) }

      it "returns true" do
        expect(project_repo.branch_exists?("auto_dependency_bump_test")).to be(true)
      end

    end

    context "when the branch doesn't exist" do

      let(:git_rev_parse_shellout) { double("Mixlib::ShellOut", error?: true, stdout: "", stderr: "fatal: Needed a single revision") }

      it "returns false" do
        expect(project_repo.branch_exists?("auto_dependency_bump_test")).to be(false)
      end

    end
  end

  describe "time since last commit" do

    let(:last_commit_unix_time) { "1459810710\n" }

    let(:git_show_shellout) { double("Mixlib::ShellOut", error?: false, stdout: last_commit_unix_time) }

    let(:now) { Time.at(1459816660) }

    before do
      expect(Mixlib::ShellOut).to receive(:new).
        with("git show -s --format=\"%ct\" auto_dependency_bump_test", cwd: "./cache/omnibus-harmony", timeout: 3600).
        and_return(git_show_shellout)
      expect(git_show_shellout).to receive(:run_command)

      expect(Time).to receive(:new).and_return(now)
    end

    it "queries git to determine the time since the last commit" do
      expect(project_repo.time_since_last_commit_on("auto_dependency_bump_test")).to eq(5950)
    end
  end

end
