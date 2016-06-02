module LitaHelpers
  # Create a notifications room to receive notifications from event handlers
  def self.included(other)
    other.class_eval do
      let(:notifications_room) { Lita::Room.create_or_update("#notifications") }

      before do
        allow_any_instance_of(Lita::Handlers::BumpbotHandler).to receive(:source_by_name) { |name| notifications_room }

        lita_config = Lita.config.handlers.versioner
        lita_config.jenkins_username = "ci"
        lita_config.jenkins_api_token = "ci_api_token"
        lita_config.trigger_real_builds = true
        lita_config.cache_directory = File.join(tmpdir, "cache")
        lita_config.sandbox_directory = File.join(lita_config.cache_directory, "sandbox")
        lita_config.debug_lines_in_pm = false
        lita_config.default_inform_channel = "default_notifications"
        lita_config.polling_interval = nil
      end
    end
  end

  def reply_lines
    replies.flat_map { |r| r.lines }.map { |l| l.chomp }
  end

  def reply_string
    reply_lines.map { |l| "#{l}\n" }.join("")
  end
end
