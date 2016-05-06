require "spec_helper"
require "lita/build_in_progress_detector"

RSpec.describe Lita::BuildInProgressDetector do

  ##
  # NOTE: these examples have a lot of extra content removed. If you need to
  # generate a new sample, you can navigate in your browser to a particular job
  # or build, then add `/api/json?pretty=true` to the URL path.

  JOB_JSON = %q{
    {
      "description" : "Build job for the 'chefdk' Build pipeline.",
      "displayName" : "chefdk-build",
      "name" : "chefdk-build",
      "builds" : [
        {
          "number" : 162,
          "url" : "http://manhattan.ci.chef.co/view/Chefdk/job/chefdk-build/162/"
        },
        {
          "number" : 161,
          "url" : "http://manhattan.ci.chef.co/view/Chefdk/job/chefdk-build/161/"
        },
        {
          "number" : 160,
          "url" : "http://manhattan.ci.chef.co/view/Chefdk/job/chefdk-build/160/"
        },
        {
          "number" : 159,
          "url" : "http://manhattan.ci.chef.co/view/Chefdk/job/chefdk-build/159/"
        }
      ],
      "lastCompletedBuild" : {
        "number" : 162,
        "url" : "http://manhattan.ci.chef.co/view/Chefdk/job/chefdk-build/162/"
      },
      "property" : [
        {
          "parameterDefinitions" : [
            {
              "defaultParameterValue" : {
                "name" : "GIT_REF",
                "value" : "master"
              },
              "description" : "Git revision, branch or tag to build.",
              "name" : "GIT_REF",
              "type" : "StringParameterDefinition"
            },
            {
              "defaultParameterValue" : {
                "name" : "APPEND_TIMESTAMP",
                "value" : true
              },
              "description" : "If false the Omnibus build will be executed with the `--no-timestamp` option.",
              "name" : "APPEND_TIMESTAMP",
              "type" : "BooleanParameterDefinition"
            }
          ]
        }
      ]
    }
  }

  BUILD_JSON = %q{
    {
      "actions" : [
        {
          "parameters" : [
            {
              "name" : "GIT_REF",
              "value" : "master"
            }
          ]
        }
      ]
    }
  }

  let(:pipeline_name) { "chefdk" }

  let(:jenkins_username) { "bobotclown" }

  let(:jenkins_api_token) { "0d8ff121f765fd302861209f09f2a0ea" }

  subject(:build_in_progress_detector) do
    described_class.new(pipeline: pipeline_name,
                        jenkins_username: jenkins_username,
                        jenkins_api_token: jenkins_api_token)
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

  it "has a list of jobs to query for in-progress builds" do
    expect(build_in_progress_detector.jenkins_jobs).to eq(%w{ chefdk-build chefdk-test })
  end

  context "when connecting to jenkins" do

    it "configures a Jenkins HTTP API connection with a username and API token" do
      expect(build_in_progress_detector.jenkins_api.username).to eq(jenkins_username)
      expect(build_in_progress_detector.jenkins_api.api_token).to eq(jenkins_api_token)
    end

  end

  context "when jenkins returns job data without error" do

    before do
      expect(build_in_progress_detector).to receive(:builds_data_for_job).
        with("chefdk-build").
        and_return(build_job_json_response)

      expect(build_in_progress_detector).to receive(:builds_data_for_job).
        with("chefdk-test").
        and_return(test_job_json_response)
    end

    context "when the jenkins API shows no builds in progress" do

      let(:build_job_json_response) { JOB_JSON }

      let(:test_job_json_response) { JOB_JSON }

      it "indicates there are no conflicting builds in progress" do
        expect(build_in_progress_detector.conflicting_build_running?).to be(false)
      end

    end

    context "when the jenkins API shows builds in progress" do

      let(:build_job_json_response) do
        build_data = FFI_Yajl::Parser.parse(JOB_JSON)
        build_data["lastCompletedBuild"]["number"] = 160
        FFI_Yajl::Encoder.encode(build_data)
      end

      let(:test_job_json_response) { JOB_JSON }

      let(:build_162_data) { BUILD_JSON }

      let(:build_161_data) { BUILD_JSON }

      before do
        expect(build_in_progress_detector).to receive(:data_for_build).
          with("chefdk-build", 162).
          and_return(build_162_data)
        expect(build_in_progress_detector).to receive(:data_for_build).
          with("chefdk-build", 161).
          and_return(build_161_data)
      end

      context "but none of the builds are relevant to the dependency updater" do

        it "indicates there are no conflicting builds in progress" do
          expect(build_in_progress_detector.conflicting_build_running?).to be(false)
        end

      end

      context "and there is a conflicting build in one of the jobs" do

        let(:build_161_data) do
          %q{
            {
              "actions" : [
                {
                  "parameters" : [
                    {
                      "name" : "GIT_REF",
                      "value" : "auto_dependency_bump_test"
                    }
                  ]
                }
              ]
            }
          }
        end

        it "indicates there is a conflicting build in progress" do
          expect(build_in_progress_detector.conflicting_build_running?).to be(true)
        end

      end

    end

  end

end
