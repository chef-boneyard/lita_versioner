require_relative "../data_bot/bot"
require_relative "jenkins_listener"
require_relative "jenkins_server"
require_relative "jenkins_pipeline"
require_relative "jenkins_build"
require "uri"

module LitaVersioner
  module PipelineBot
    class Bot < DataBot::Bot
      #
      # The list of tracked Jenkins serverss.
      #
      # @return [Array<JenkinsServer>] The list of Jenkins servers.
      #
      def jenkins_servers
        data["jenkins_servers"].map { |server| jenkins_server(url) }
      end

      #
      # Create a new PipelineBot.
      #
      # @param config [Lita::Config] Bot configuration.
      #
      def initialize(config)
        @config = config
        load_data
      end

      #
      # Get the Jenkins server object with the given URL.
      #
      def jenkins_server(url)
        url = URI(url)
        url.path = ""
        url = url.to_s
        server = JenkinsServer.new(self, "url" => url)
        unless data["jenkins_servers"].include?(url)
          data["jenkins_servers"] << url
          data["jenkins_servers"].uniq!
        end
        server
      end

      #
      # Get the Jenkins pipeline with the given URL.
      #
      def jenkins_pipeline(url)
        JenkinsPipeline.new(self, url)
      end

      #
      # Get the Jenkins build with the given URL.
      #
      # @return [JenkinsBuild] The Jenkins build with the given URL.
      #
      def jenkins_build(url)
        JenkinsBuild.new(self, url)
      end

      #
      # The Jenkins server object that grabs pipeline build information from the server.
      #
      # @return [JenkinsPipelineReport::Jenkins::Server]
      #
      def jenkins
        @jenkins ||= begin
          jenkins_cache = File.join(cache_directory, ".jenkins")
          cache = JenkinsPipelineReport::Jenkins::Cache.new(cache_directory: jenkins_cache, username: config.jenkins_username, api_token: jenkins_api_token, logger: self)
          cache.server(config.jenkins_endpoint)
        end
      end

      #
      # The Jenkins report object that creates build summary reports.
      #
      # @return [JenkinsPipelineReport::Report::Cache] The Jenkins report object
      #   that creates (and caches) build summary reports.
      #
      def reports
        @reports ||= begin
          reports_cache = File.join(cache_directory, "reports")
          JenkinsPipelineReport::Report::Cache.new(cache_directory: reports_cache, logger: self)
        end
      end

      def slack_message
        attachment = {}
        attachment[:color] = jenkins_listener.working_properly? ? "good" : "danger"
        attachment[:text] << "Jenkins listener #{jenkins_listener.status} (<#{handler_url(jenkins_listener.last_handler_id)}/handler.log|last attempt>}). <#{config.lita_url}|Web interface>"
        { attachments: [ attachment ] }
      end
    end
  end
end
