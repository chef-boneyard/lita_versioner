module LitaVersioner
  module PipelineBot
    class JenkinsListener < DataBot::Data
      def redis_path
        "#{bot.redis_path}:jenkins_listener"
      end

      attr_reader :start_time
      attr_reader :current_run
      attr_reader :current_run_id

      def last_run
        Time.at(data["last_run"])
      end

      def last_run_id
        data["last_run_id"]
      end

      def last_run_succeeded
        data["last_run_succeeded"]
      end

      def tolerance
        data["tolerance"] || 10*60
      end

      def frequency
        data["frequency"] || 1*60
      end

      def working_properly?
        status == "working properly"
      end

      def status
        if !last_run
          "never run"
        elsif (last_run - Time.now.utc) > tolerance
          "not running"
        elsif last_run_succeeded
          "working properly"
        else
          "failing"
        end
      end

      def initialize(bot)
        super({})
        @bot = bot
        start
      end

      def slack_message
        if last_run
          last_run_text = " Last run: <#{handler_log_url(last_run_id)}|#{format_duration(Time.last_run)} ago>"
        end
        if current_run
          current_run_text = " Current run: started <#{handler_log_url(last_run_id)}|#{format_duration(Time.now.utc-current_run)} ago>"
        end

        {
          attachments: [{
            color: working_properly? ? "good" : "danger",
            text: "Jenkins listener #{status}.#{last_run_text}#{current_run_text} Frequency: #{format_duration(frequency)}."
          }]
        }
      end

      def start
        handle_task "Start listener" do
          @start_time = Time.now.utc
          robot = handler.robot
          every(frequency) do |timer|
            # We need to create a new handler each time for a different handler ID
            # and run.
            Bot.with(PipelineHandler.new(robot)) do |bot|
              handle "Jenkins refresh timer" do
                bot.jenkins_listener.refresh
              end
            end
          end
        end
      end

      def refresh
        handle_task "Jenkins refresh" do
          raise "Refresh already running as #{current_run_id}!" if current_run_id
          @current_run_id = handler_id
          begin
            @current_run = Time.now.utc
            begin
              bot.jenkins_servers.each do |server|
                server.refresh
              end
              data["last_run_succeeded"] = true
            rescue
              data["last_run_succeeded"] = false
            end
            data["last_run"] = current_run
            data["last_run_id"] = current_run_id
            save_data
          ensure
            @current_run = nil
            @current_run_id = nil
          end
        end
      end
    end
  end
end
