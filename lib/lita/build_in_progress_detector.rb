require "ffi_yajl"
require "lita/jenkins_http"

module Lita
  class BuildInProgressDetector

    PIPELINE_JOBS = %w[ build test ].freeze

    VERSION_BUMPER_GIT_REF = "auto_dependency_bump_test".freeze

    JENKINS_ENDPOINT = "http://manhattan.ci.chef.co/".freeze

    attr_reader :pipeline
    attr_reader :jenkins_username
    attr_reader :jenkins_api_token

    def initialize(pipeline: nil, jenkins_username: nil, jenkins_api_token: nil)
      @pipeline = pipeline
      @jenkins_username = jenkins_username
      @jenkins_api_token = jenkins_api_token
    end

    def jenkins_jobs
      PIPELINE_JOBS.map { |j| "#{pipeline}-#{j}" }
    end

    def conflicting_build_running?
      !conflicting_builds_in_progress.empty?
    end

    # @api private
    def conflicting_builds_in_progress
      jenkins_jobs.inject([]) do |builds, job|
        all_builds_in_progress = builds_in_progress_for_job(job)
        conflicting_builds = all_builds_in_progress.select { |b| conflicting_build?(job, b) }
        builds.concat(conflicting_builds)
        builds
      end
    end

    # @api private
    def conflicting_build?(job, build_number)
      json_data = data_for_build(job, build_number)
      build_data = FFI_Yajl::Parser.parse(json_data)
      build_params = build_data["actions"].find { |a| a.key?("parameters") }["parameters"]
      git_ref = build_params.find {|p| p.key?("name") && p["name"] == "GIT_REF"}["value"]
      git_ref == VERSION_BUMPER_GIT_REF
    end

    # @api private
    def builds_in_progress_for_job(job)
      json_data = builds_data_for_job(job)
      job_data = FFI_Yajl::Parser.parse(json_data)

      last_completed_build_number = job_data["lastCompletedBuild"]["number"]
      in_progress_build_data = job_data["builds"].select do |build|
        build["number"] > last_completed_build_number
      end
      in_progress_build_data.map { |b| b["number"] }
    end

    # @api private
    def data_for_build(job, build_number)
      jenkins_api.get("/job/#{job}/#{build_number}/api/json?pretty=true").body
    end

    # @api private
    def builds_data_for_job(job)
      jenkins_api.get("/job/#{job}/api/json?pretty=true").body
    end

    # @api private
    def jenkins_api
      JenkinsHTTP.new(base_uri: JENKINS_ENDPOINT, username: jenkins_username, api_token: jenkins_api_token)
    end

  end
end
