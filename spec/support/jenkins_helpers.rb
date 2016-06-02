#
# Helps you simulate a jenkins server talking to JenkinsHTTP.
#
# @example
#
#  with_jenkins_server "http://manhattan.ci.chef.co" do
#    jenkins_data "jobs" => [
#      {
#        "name" => "chef-dk-build",
#        "builds" => [
#           { "result" => "FAILURE" },
#           { "result" => "SUCCESS" },
#           { "result" => nil },
#        ]
#     },
#     {
#        "name" => "chef-dk-test",
#        "builds" => [
#          { "result" => "FAILURE" }
#        ]
#     }
#   ]
# end
#
module JenkinsHelpers
  def self.included(other)
    other.class_eval do
      def self.with_jenkins_server(jenkins_url, description = "with a jenkins server at #{jenkins_url}", &block)
        if block_given?
          context description do
            with_jenkins_server(jenkins_url)
            class_eval(&block)
          end
        else
          let(:jenkins_url) { jenkins_url }
          include WithJenkinsServer
          extend WithJenkinsServerTestDefinitions
        end
      end
    end
  end

  module WithJenkinsServerTestDefinitions
    def jenkins_data(value)
      before do
        jenkins_data(value)
      end
    end

    def jenkins_job(path, *args)
      before do
        add_jenkins_job path, *args
      end
    end
  end

  module WithJenkinsServer
    def self.included(other)
      other.class_eval do
        let(:jenkins_http) { double("jenkins_http") }
        before do
          allow(LitaVersioner::JenkinsHTTP).to receive(:new).
            with(base_uri: "http://manhattan.ci.chef.co/", username: "ci", api_token: "ci_api_token").
            and_return(jenkins_http)

          allow(jenkins_http).to receive(:get).with(match(%r{^/job/([^/]+)/api/json\b.*})) do |path|
            jenkins_job_response(path)
          end

          allow(jenkins_http).to receive(:get).with(match(%r{^/job/([^/]+)/(\d+)/api/json\b.*})) do |path|
            jenkins_build_response(path)
          end
        end
      end
    end

    def jenkins_data(jenkins_data = nil)
      if jenkins_data
        @jenkins_data = normalize_jenkins_data(jenkins_data)
      end
      raise "jenkins_data not set!" unless @jenkins_data
      @jenkins_data
    end

    def jenkins_job_response(path)
      job_name = path.split("/", 4)[2]
      if job = jenkins_data["jobs"].find { |job| job["name"] == job_name }
        fake_response(job.merge(
          "builds" => job["builds"].reverse,
          "allBuilds" => job["builds"].reverse
        ))
      else
        fake_error_response(404)
      end
    end

    def jenkins_build_response(path)
      job_name = path.split("/", 5)[2]
      number = path.split("/", 5)[3].to_i
      if job = jenkins_data["jobs"].find { |job| job["name"] == job_name }
        if build = job["builds"].find { |build| build["number"] == number }
          return fake_response(build)
        end
      end
      fake_error_response(404)
    end

    def expect_jenkins(path, json)
      expect(jenkins_http).to receive(:get).
        with("#{path}/api/json?pretty=true").
        and_return(fake_response(json))
    end

    def expect_jenkins_build(path, git_ref:, initiated_by:, expire_cache: false)
      expect(jenkins_http).to receive(:post).
        with("#{path}/buildWithParameters",
          {
            "GIT_REF" => git_ref,
            "EXPIRE_CACHE" => expire_cache,
            "INITIATED_BY" => initiated_by,
          }
        )
    end

    def fake_response(json, code: 200)
      response = double("json")
      allow(response).to receive(:code).and_return(code)
      allow(response).to receive(:body).and_return(FFI_Yajl::Encoder.encode(json))
      response
    end

    def fake_error_response(code)
      reason = "Not Found" if code == 404
      response = double("response")
      allow(response).to receive(:code).and_return(code)
      allow(response).to receive(:body).and_return(<<-EOM.gsub(/^        /, ""))
        <html>
        <head>
        <meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1"/>
        <title>Error #{code} #{reason}</title>
        </head>
        <body><h2>HTTP ERROR #{code}</h2>
        <p>Problem accessing /job/harmony-trigger-ad_hdoc/api/json. Reason:
        <pre>    #{reason}</pre></p><hr /><i><small>Powered by Jetty://</small></i><br/>
        </body>
        </html>
      EOM
      response
    end

    def normalize_jenkins_data(jenkins_data)
      # Process all the jobs
      if jenkins_data["jobs"].is_a?(Hash)
        jenkins_data["jobs"] = jenkins_data["jobs"].map do |name, value|
          value = { "builds" => value } if value.is_a?(Array)
          value.merge("name" => name)
        end
      end
      jenkins_data["jobs"] ||= []
      jenkins_data["jobs"].map! { |job| normalize_jenkins_job(job) }
      jenkins_data
    end

    def normalize_jenkins_job(job)
      job = job.dup
      job["url"] ||= "#{jenkins_url}/job/#{job["name"]}"

      job["builds"] ||= []

      # Autonumber and normalize the builds
      next_build_number = job["nextBuildNumber"] || 1
      job["builds"] = job["builds"].map do |build|
        number = build["number"] || next_build_number
        next_build_number = number + 1 if number >= next_build_number
        normalize_jenkins_build(job, build.merge("number" => number))
      end

      # Sort builds by increasing number, set next build number
      job["builds"].sort_by! { |build| build["number"] }
      job["nextBuildNumber"] = next_build_number

      job["lastCompletedBuild"] = job["builds"].find { |b| b["result"] }

      job
    end

    def normalize_jenkins_build(job, build)
      build["url"] = "#{jenkins_url}/job/#{job["name"]}/#{build["number"]}"
      # Handle :parameters -> "actions" => [ { "parameters" => [ { "name" => name, "value" => value }]}]
      if parameters = build.delete(:parameters)
        build["actions"] ||= []
        param_action = build["actions"].find { |a| a.has_key?("parameters") }
        unless param_action
          param_action = { "parameters" => [] }
          build["actions"] << param_action
        end
        param_action["parameters"].reject! { |p| parameters.has_key?(p["name"]) }
        parameters.each do |name, value|
          param_action["parameters"] << { "name" => name, "value" => value }
        end
      end
      build
    end
  end
end
