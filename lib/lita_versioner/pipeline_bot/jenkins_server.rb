require_relative "jenkins_build"

module LitaVersioner
  module PipelineBot
    #
    # Represents a tracked server (which may or may not be tracked).
    #
    class JenkinsServer < DataBot::Data
      #
      # The URL to the Jenkins server
      #
      # @return [String] The URL to the Jenkins server.
      #
      # @example
      #     server.url #=> "http://manhattan.ci.chef.co"
      #
      attr_reader :url

      def redis_path
        "#{bot.redis_path}:jenkins_server:#{url}"
      end

      #
      # The last time this `refresh_builds` was called on this server.
      #
      # @return [DateTime] The time the server was last updated.
      #
      def last_refresh
        Time.at(data["last_refresh"])
      end

      def last_refresh_error
        data["last_refresh_error"]
      end

      def last_refresh_handler_id
        data["last_refresh_handler_id"]
      end

      #
      # Get all available pipelines.
      #
      # @return [Array<JenkinsPipeline>] Pipelines on the server.
      #
      def pipelines
        data["pipelines"].map { |job_url| bot.pipeline(job_url) }
      end

      #
      # Create a new server.
      #
      # @param bot [Bot] The bot this server is a part of.
      # @param url [String] The URL to the server.
      #
      # @example
      #    JenkinsServer.new(bot, "http://manhattan.ci.chef.co")
      #
      # @api private Use bot.server(url) instead.
      #
      def initialize(bot, url)
        super(data)
        @bot = bot
      end

      #
      # Get the Jenkins server API object for this server.
      #
      # @return [JenkinsPipelineReport::Jenkins::Server] The Jenkins server API
      #   object for this server.
      #
      def server
        bot.jenkins_cache.server(url)
      end

      #
      # Load or refresh pipeline and build data for this server.
      #
      def refresh
        handle_task "Refresh Jenkins server #{url}" do
          refresh_time = Time.now.utc.to_i
          begin
            new_data, builds = refresh_builds(refresh_time)
            triggers = refresh_time.map { |build| build.trigger.url }.uniq
            pipelines = Set.new
            triggers.each do |trigger|
              build = bot.build(trigger.url)
              build.refresh
              pipelines.add(trigger.job.url)
            end
            # Refresh the pipelines themselves now that jobs have been refreshed.
            pipelines.each do |url|
              bot.pipeline(url).refresh
            end
            new_data["last_refresh_error"] = nil
          rescue
            new_data = data || {}
            new_data["last_refresh_error"] = $!.to_s
            raise
          ensure
            new_data["last_refresh"] = refresh_time.to_i
            new_data["last_refresh_handler_id"] = handler_id
            @data = new_data
            save_data
          end
        end
      end

      def slack_message
        if last_refresh_error
          {
            color: "danger",
            attachments: [{
              "Jenkins <#{url}|#{URI(url).server}> tried and failed to refresh (<#{handler_log_url(last_refresh_handler_id)}|Log>) at #{format_ago(last_refresh)}. It has #{pipelines.size} pipelines and #{in_progress_builds.size} in-progress builds." :
            }]
          }
        elsif last_refresh
          {
            color: "good",
            attachments: [{
              "Jenkins <#{url}|#{URI(url).server}> was last refreshed at #{format_ago(last_refresh)}. It has #{pipelines.size} pipelines and #{in_progress_builds.size} in-progress builds." :
            }]
          }
        else
          {
            color: "danger",
            attachments: [{
              "Jenkins <#{url}|#{URI(url).server}> has never been refreshed."
            }]
          }
        end
      end

      private

      def refresh_builds(refresh_time)
        # Grab all the jobs and the last build for each
        result = server.api_get("", "tree=jobs[url,lastBuild[number],activeConfigurations[url,lastBuild[number]],actions[processes[url,lastBuild[number]]]]")
        jobs = {}
        builds = []
        result["jobs"].each do |job|
          # Top level jobs
          jobs[job["url"]] = refresh_job_builds(job, builds)

          # Matrix jobs
          if job["activeConfigurations"]
            job["activeConfigurations"].each { |job| jobs[job["url"]] = refresh_job_builds(job, builds) }
          end

          # Processes
          job["actions"].each do |action|
            if action["processes"]
              action["processes"].each { |job| jobs[job["url"]] = refresh_job_builds(job, builds) }
            end
          end
        end

        debug "Found new builds #{builds}"

        builds.each do |build|
          build.invalidate
        end

        new_data = {
          "in_progress_builds" => builds.select { |build| build.result.nil? }.map { |build| build.url },
          "jobs" => jobs,
          "pipelines" => result["jobs"].map { |job| job["url"] }
        }

        [ new_data, builds ]
      end

      def refresh_job_builds(job_data, builds)
        # See if there are any new builds
        old_job = data["jobs"][job_data["url"]]
        if old_job && old_job["last_build_number"]
          if job_data["lastBuild"] && job_data["lastBuild"]["number"] &&
            job_data["lastBuild"]["number"] > old_job["last_build_number"]
            new_builds = job.builds.select { |build| build.number > old_job["last_build_number"] }
          else
            new_builds = []
          end
        else
          new_builds = job.builds
        end

        builds += new_builds
        # Return the last build number
        new_builds.map { |build| build.number }.max || (old_job && old_job["last_build_number"])
      end
    end
  end
end
