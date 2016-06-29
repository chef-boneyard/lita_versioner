require_relative "../data_bot/data"

module LitaVersioner
  module PipelineBot
    #
    # Represents a Jenkins pipeline starting from a given trigger.
    #
    class JenkinsPipeline < DataBot::Data
      #
      # The URL to the Jenkins job triggering this pipeline.
      #
      # @return [String] The URL to the Jenkins job triggering this pipeline.
      #
      # @example
      #    pipeline.url #=> "http://manhattan.ci.chef.co/job/chef-trigger-release"
      #
      attr_reader :url

      def redis_path
        "#{bot.redis_path}:jenkins_pipeline:#{url}"
      end

      #
      # The last completed build in this pipeline.
      #
      # @return [JenkinsBuild] The last completed build in this pipeline.
      #
      def last_build
        bot.build(data["last_build"]) if data["last_build"]
      end

      #
      # The Jenkins job used as the pipeline trigger.
      #
      def job
        server = bot.jenkins_cache.server(url)
        server.job(URI(url).path)
      end

      #
      # Create a new Jenkins pipeline object
      #
      # @param bot [Bot] The bot this pipeline is under.
      # @param url [String] The URL to this pipeline.
      #
      def initialize(bot, url)
        @bot = bot
        @url = url
      end

      def refresh
        handle_task "Refresh pipeline #{url}" do
          triggers = job.builds.select { |job| job.upstreams.empty? }

          # Go in reverse, from highest to lowest.
          result = nil
          cause = nil
          triggers.reverse_each do |trigger|
            report = job.build("report").report
            case report["result"]
            when "FAILURE", "SUCCESS"
              result = "FAILURE"
              cause = report["failure_cause"]
              break
            end
          end

          old_data = data.dup
          data["result"] = status
          data["cause"] = cause
          data["build"] = report.trigger.url
          data["last_build"] = latest_in_progress
          save_data
          if data["result"] != old_data["result"]
            send_event("cause_changed")
            send_event("result_changed")
          elsif data["cause"] != old_data["cause"]
            send_event("cause_changed")
          end
        end
      end

      def send_event(event)
        super(event, "jenkins_pipeline", "url" => data["url"], "result" => data["result"], "cause" => data["cause"]) do |subscription|
          # Remove the oldest message if there are 2 already.
          old_messages = old_messages(subscription.channel)
          if old_messages.size > 1
            old_message = old_messages.shift
            # Don't delete messages that have scrolled off.
            old_message.delete if old_message.visible?
          end
          messages = old_message
          messages = old_message
          messages << subscription.send(slack_message(event))
          data["old_messages"] = messages.map { |message| [ message.channel, message.ts ]}
          data["old_messages"][subscription.channel] = []
        end
      end

      def slack_message(event=nil)
        case event
        when "result_changed"
          prefix = "#{name} is now #{data["result"] == "SUCCESS" ? "green" : "red"}"
        when "cause_changed"
          prefix = "#{name} failed for a different reason: "
        else
          prefix = "#{name} is #{data["result"] == "SUCCESS" : "green" : "red"}"
        end

        slack_message = last_build.slack_message
        slack_message[:attachments][:text] = "#{prefix}: #{slack_message[:attachments][:text]}"
        slack_message
      end
    end
  end
end
