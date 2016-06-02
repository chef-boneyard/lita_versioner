require "spec_helper"
require "lita_versioner/build_in_progress_detector"

RSpec.describe LitaVersioner::BuildInProgressDetector do

  ##
  # NOTE: these examples have a lot of extra content removed. If you need to
  # generate a new sample, you can navigate in your browser to a particular job
  # or build, then add `/api/json?pretty=true` to the URL path.

  let(:trigger_name) { "chefdk-trigger-release" }
  let(:pipeline_name) { "chefdk" }
  let(:jenkins_username) { "bobotclown" }
  let(:jenkins_api_token) { "0d8ff121f765fd302861209f09f2a0ea" }
  let(:jenkins_endpoint) { "http://manhattan.ci.chef.co" }
  let(:target_git_ref) { "our_target_branch" }
  let(:last_completed_build) { 162 }

  subject(:build_in_progress_detector) do
    described_class.new(trigger: trigger_name,
                        pipeline: pipeline_name,
                        jenkins_username: jenkins_username,
                        jenkins_api_token: jenkins_api_token,
                        jenkins_endpoint: jenkins_endpoint,
                        target_git_ref: target_git_ref
                       )
  end

  it "has a pipeline name" do
    expect(build_in_progress_detector.pipeline).to eq(pipeline_name)
  end

  it "has a jenkins username" do
    expect(build_in_progress_detector.jenkins_username).to eq(jenkins_username)
  end

  it "has a jenkins API token" do
    expect(build_in_progress_detector.jenkins_api_token).to eq(jenkins_api_token)
  end

  it "has a jenkins endpoint" do
    expect(build_in_progress_detector.jenkins_endpoint).to eq(jenkins_endpoint)
  end

  it "has a target git ref" do
    expect(build_in_progress_detector.target_git_ref).to eq(target_git_ref)
  end

  it "has a list of jobs to query for in-progress builds" do
    expect(build_in_progress_detector.jenkins_jobs).to eq(%w{ chefdk-trigger-release chefdk-build chefdk-test chefdk-release })
  end

  context "when connecting to jenkins" do

    it "configures a Jenkins HTTP API connection with a username and API token" do
      expect(build_in_progress_detector.jenkins_api.username).to eq(jenkins_username)
      expect(build_in_progress_detector.jenkins_api.api_token).to eq(jenkins_api_token)
    end

  end

end
