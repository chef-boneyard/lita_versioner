require_relative "../data_bot/data"

module LitaVersioner
  module PipelineBot
    #
    # Represents a full multi-stage Jenkins pipeline build, with retries
    # and matrix builds, from start to finish.
    #
    class JenkinsBuild < DataBot::Data
      #
      # The URL to the trigger build.
      #
      # @return [String] The URL to the trigger build.
      #
      # @example
      #    build.url #=> "http://manhattan.ci.chef.co/job/chef-trigger-release/1/"
      #
      attr_reader :url

      def initialize(bot, url)
        @bot = bot
        @url = url
      end

      def pipeline
        bot.pipeline(File.dirname(url))
      end

      def build
        bot.reports.build(url)
      end

      def report
        build.report
      end

      def refresh
        handle_task "Refresh build #{url}" do
          # If we already have a report, check to see what has changed so that we
          # can fire the proper events.
          old_report = build.report?
          new_report = build.refresh_report

          send_event("started") unless old_report

          # Reports have stages in reverse order
          new_report.stages.reverse_each do |name, new_stage|
            old_stage = old_report && old_report["stages"][name]
            if old_stage
              if new_stage["url"] != old_stage["url"]
                send_event("stage_started", "retry" => true)
              else
                old_result = old_stage["result"]
              end
            else
              send_event("stage_started")
            end

            if new_stage["result"] != old_result
              send_event("stage_completed", "result" => new_stage["result"]) unless new_stage["result"] != "IN PROGRESS"
            end
          end

          if old_report.nil? || new_report["result"] != old_report["result"]
            send_event("completed", "result" => new_report["result"]) unless new_report["result"] == "IN PROGRESS"
          end
        end
      end

      def change_name
        "#{project.name} #{build.report["change"]["version"]}"
      end

      def commit_url
        if report["change"]
          if git_remote = report["change"]["git_remote"]
            git_commit = build.report["change"]["git_commit"]
            # git@github.com:chef/chef
            change_url = git_remote.sub(%r{^(\w+@)?github\.com:}, "https://github.com/")
            # git://github.com/chef/chef
            change_url.sub!(%r{git://(\w+@)?github.com/}, "https://github.com/")
            # chef/chef
            change_url = "https://github.com/#{change_url}" if change_url =~ %r{^\w+/%w+$}
            # remove .git
            change_url.sub!(%r{\.git$}, "")
            return "#{change_url}/commit/#{git_commit}"
          end
        end
      end

      #
      # Build the Slack message to be sent for this build.
      #
      def slack_message
        change_identifier = "<#{commit_url}|#{change_name}>"
        stage_name, last_stage = report["stages"].first
        jenkins_url = last_stage["url"]
        case report["result"]
        when "SUCCESS"
          {
            attachments: {
              text: "#{change_identifier} build <#{jenkins_url}|succeeded> in #{report["duration"]}.",
              color: "good"
            }
          }
        when "IN PROGRESS"
          {
            attachments: {
              text: "#{change_identifier} build running: currently in <#{jenkins_url}|#{stage_name}>.",
              color: "warning"
            }
          }
        else
          run_name, last_run = last_stage["runs"] && last_stage["runs"].last
          if run_name
            run_text = " <#{last_run["url"]}|#{run_name} log>"
          end
          {
            attachments: {
              text: "#{change_identifier} pipeline #{report["result"].downcase} due to <#{jenkins_url}|#{report["failure_cause"]}>.#{run_text}",
              color: "danger"
            }
          }
        end
      end
    end
  end
end
