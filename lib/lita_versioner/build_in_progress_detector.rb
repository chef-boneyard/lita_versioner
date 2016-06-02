require "ffi_yajl"
require_relative "jenkins_http"

module LitaVersioner
  class BuildInProgressDetector

    PIPELINE_JOBS = %w{ build test release }.freeze

    attr_reader :pipeline
    attr_reader :trigger
    attr_reader :jenkins_username
    attr_reader :jenkins_api_token
    attr_reader :jenkins_endpoint
    attr_reader :target_git_ref

    def initialize(pipeline: nil, trigger: nil, jenkins_username: nil, jenkins_api_token: nil, jenkins_endpoint: nil, target_git_ref: nil)
      @pipeline = pipeline
      @trigger = trigger
      @jenkins_username = jenkins_username
      @jenkins_api_token = jenkins_api_token
      @jenkins_endpoint = jenkins_endpoint
      @target_git_ref = target_git_ref
    end

    def jenkins_jobs
      [ trigger ] + PIPELINE_JOBS.map { |j| "#{pipeline}-#{j}" }
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
      git_ref = build_params.find { |p| p.key?("name") && p["name"] == "GIT_REF" }["value"]
      git_ref == target_git_ref
    end

    # @api private
    def builds_in_progress_for_job(job)
      json_data = builds_data_for_job(job)
      job_data = FFI_Yajl::Parser.parse(json_data)

      in_progress_build_data = job_data["builds"].select do |build|
        build["result"].nil?
      end
      in_progress_build_data.map { |b| b["number"] }
    end

    # @api private
    def data_for_build(job, build_number)
      jenkins_api.get("/job/#{job}/#{build_number}/api/json?pretty=true").body
    end

    # @api private
    def builds_data_for_job(job)
      jenkins_api.get("/job/#{job}/api/json?pretty=true&tree=name,url,upstreamProjects[name],downstreamProjects[name],builds[number,result,parameters[name,value]]]").body
    end

    # @api private
    def jenkins_api
      JenkinsHTTP.new(base_uri: jenkins_endpoint, username: jenkins_username, api_token: jenkins_api_token)
    end

  end
end
