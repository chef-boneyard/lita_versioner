require "spec_helper"
require "tmpdir"
require "fileutils"

require "lita/project_repo"

describe Lita::ProjectRepo do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_name) { "lita-versioner" }
  let(:project_url) { "https://github.com/chef/#{project_name}.git" }
  let(:project_repo) { Lita::ProjectRepo.new(project_url) }

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
end
