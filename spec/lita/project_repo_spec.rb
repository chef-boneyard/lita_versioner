require "spec_helper"
require "tmpdir"
require "fileutils"

require "lita/project_repo"

describe Lita::ProjectRepo do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_name) { "lita-versioner" }
  let(:project_url) { "https://github.com/chef/#{project_name}.git" }
  let(:version_bump_cmd) { nil }
  let(:project_repo) { Lita::ProjectRepo.new(project_url, version_bump_cmd) }

  before do
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
    let(:version_file) { File.join(project_repo.repo_directory, "VERSION") }
    before do
      original_run_command = project_repo.method(:run_command)
      allow(project_repo).to receive(:run_command) do |command|
        # Do not push the branch for real. But run a status command to be able
        # correctly return a Shellout object.
        if command == "git push origin master"
          command = "git status"
        end
        original_run_command.call(command)
      end

      Dir.mkdir(project_repo.repo_directory)
      FileUtils.touch(version_file)
      File.open(version_file, "w+") do |f|
        f.puts "1.1.0"
      end
      project_repo.run_command("git init .")
    end

    it "can bump the version" do
      project_repo.bump_version
      expect(File.read(version_file)).to match /1.1.1/
      expect(project_repo.run_command("git log").stdout).to match /Automatic version bump for lita-versioner by lita-versioner./
    end
  end

end
