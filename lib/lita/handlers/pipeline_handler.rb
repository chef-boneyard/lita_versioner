require_relative "../../lita_versioner/pipeline_bot/bot"

module Lita
  module Handlers
    class PipelineHandler < BumpbotHandler

      Bot = PipelineBot::Bot

      # Overall Status
      desc "Get pipeline bot status"
      Bot.command "pipeline status" do
        bot
      end

      TARGET_HELP = "[@USER|#CHANNEL] is the user or channel (default is current user or channel)."
      SERVER_HELP = "SERVER is the server url, e.g. http://manhattan.ci.chef.co."
      JOB_HELP = "JOB is the job url, e.g. http://manhattan.ci.chef.co/job/chef-trigger-release/."
      BUILD_HELP = "BUILD is a build url, e.g. http://manhattan.ci.chef.co/job/chef-trigger-release/20/."

      # Subscriptions
      desc "List all pipeline subscriptions"
      Bot.command "pipeline subscriptions" do
        bot.subscriptions
      end
      desc "Show subscription. #{TARGET_HELP}"
      Bot.command "pipeline subscription show [@USER|#CHANNEL]" do |target|
        bot.subscriptions[target || current_target]
      end
      desc "Subscribe to absolutely everything. #{TARGET_HELP}"
      Bot.command "pipeline subscribe [@USER|#CHANNEL]" do |target|
        bot.subscribe(target || current_target, {}, {})
      end
      desc "Subscribe to a pipeline. #{TARGET_HELP} #{JOB_HELP}"
      Bot.command "pipeline subscribe [@USER|#CHANNEL] to JOB" do |target, job|
        bot.subscribe(target || current_target, { "event" => "status_changed", "data_type" => "pipeline" }, {})
      end
      desc "Unsubscribe from everything. #{TARGET_HELP}"
      Bot.command "pipeline unsubscribe [@USER|#CHANNEL]" do |target|
        bot.unsubscribe(target || current_target)
      end

      # Jenkins Listener
      desc "Get status of the Jenkins listener."
      Bot.command "pipeline jenkins listener"  do
        bot.jenkins_listener
      end
      desc "Refresh the Jenkins listener."
      Bot.command "pipeline refresh jenkins listener" do
        bot.jenkins_listener.refresh
      end
      desc "Stop the Jenkins listener."
      Bot.command "pipeline stop jenkins listener" do
        bot.jenkins_listener.stop
      end

      # Servers
      desc "List the Jenkins servers being tracked."
      Bot.command "pipeline jenkins servers" do
        bot.jenkins_servers
      end
      desc "List the Jenkins servers being tracked."
      Bot.command "pipeline list jenkins servers" do
        bot.jenkins_servers
      end
      desc "Start tracking the given Jenkins server. #{SERVER_HELP}"
      Bot.command "pipeline add jenkins server SERVER" do |server|
        bot.add_server(server)
      end
      desc "Stop tracking the given Jenkins server. #{SERVER_HELP}"
      Bot.command "pipeline remove jenkins server SERVER" do |server|
        bot.remove_server(server)
      end
      desc "Show refresh status for the given Jenkins server. #{SERVER_HELP}"
      Bot.command "pipeline show jenkins server SERVER" do |server|
        bot.jenkins_server(server)
      end

      # Pipelines
      desc "List all Jenkins pipelines."
      Bot.command "pipeline list jenkins pipelines" do
        bot.jenkins_server.flat_map { |s| s.pipelines }
      end
      desc "List pipelines on the given Jenkins server. #{SERVER_HELP}"
      Bot.command "pipeline list jenkins pipelines for SERVER" do |server|
        bot.jenkins_server(server).pipelines
      end
      desc "Show pipeline status. #{JOB_HELP}"
      Bot.command "pipeline show jenkins pipeline JOB" do |job|
        bot.jenkins_pipeline(job)
      end

      desc "Show status for the Jenkins server, job or build. URL is the URL to the server (e.g. http://manhattan.ci.chef.co), job (e.g. http://manhattan.ci.chef.co/job/chef-trigger-release/) or build (http://manhattan.ci.chef.co/job/chef-trigger-release/20/)"
      Bot.command "pipeline show URL" do |url|
        path = URI(url).path
        if path.start_with?("/job/")
          if File.basename(path) =~ /^\d+$/
            bot.jenkins_build(url)
          else
            bot.jenkins_pipeline(url)
          end
        else
          bot.jenkins_server(url)
        end

      # Builds
      desc "List builds for the given pipeline. #{JOB_HELP}"
      Bot.command "pipeline list builds for JOB" do |job|
        bot.jenkins_server(job).in_progress_builds
      end
      desc "List all in progress builds."
      Bot.command "pipeline list in progress builds" do
        bot.jenkins_servers.flat_map { |s| s.in_progress_builds }
      end
      desc "List in progress builds for the given server or job. URL is the URL to the server (e.g. http://manhattan.ci.chef.co) or job (e.g. http://manhattan.ci.chef.co/job/chef-trigger-release/)"
      Bot.command("pipeline list in progress builds for URL") do |url|
        path = URI(url).path
        if path.start_with?("/job/")
          bot.jenkins_pipeline(url).in_progress_builds
        else
          bot.jenkins_server(url).in_progress_builds
        end
      end
      desc "Show build status."
      Bot.command "pipeline show build BUILD" do |build|
        bot.jenkins_build(build)
      end
    end
  end
end
