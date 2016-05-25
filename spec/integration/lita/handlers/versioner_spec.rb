require "spec_helper"

describe Lita::Handlers::Versioner, lita_handler: true, additional_lita_handlers: Lita::Handlers::BumpbotHandler do
  before do
    Lita.config.handlers.versioner.jenkins_username = "ci"
    Lita.config.handlers.versioner.jenkins_api_token = "ci_api_token"
    Lita.config.handlers.versioner.trigger_real_builds = false
    Lita.config.handlers.versioner.projects = {
      "harmony" => {
        pipeline: "harmony-trigger-ad_hoc",
        github_url: "git@github.com:chef/lita-test.git",
        version_bump_command: "bundle install && bundle exec rake version:bump_patch",
        version_show_command: "bundle exec rake version:show",
        dependency_update_command: "bundle install && bundle exec rake dependencies && git checkout .bundle/config",
        inform_channel: "chef-notify",
      },
    }
  end

  # We override route() - therefore, the matcher doesn't work correctly.
  #it { is_expected.to route_command("build harmony").to(:build) }
  it { is_expected.to route_http(:post, "/github_handler").to(:github_handler) }

  it "does not build without project name" do
    send_command("build")
    expect(replies[-2]).to match(/No project specified/)
  end

  it "does not build unsupported projects" do
    send_command("build chef")
    expect(replies[-2]).to match(/Invalid project/)
  end

  it "builds with master by default" do
    # The robot creates a new instance of the handler on the fly.
    # So we need this stupid hack to set expectations on any handler it creates.
    expect_any_instance_of(Lita::Handlers::Versioner).to receive(:trigger_build)
      .with("harmony-trigger-ad_hoc", "master").and_return(true)
    send_command("build harmony")
    expect(replies.last).to match(/Kicked off a build for 'harmony-trigger-ad_hoc' at ref 'master'/)
  end

  it "builds with the specified tag" do
    # The robot creates a new instance of the handler on the fly.
    # So we need this stupid hack to set expectations on any handler it creates.
    expect_any_instance_of(Lita::Handlers::Versioner).to receive(:trigger_build)
      .with("harmony-trigger-ad_hoc", "example").and_return(true)
    send_command("build harmony example")
    expect(replies.last).to match(/Kicked off a build for 'harmony-trigger-ad_hoc' at ref 'example'/)
  end

  context "github handler" do
    let(:event_type) { nil }
    let(:repository) { nil }
    let(:pull_request_action) { "closed" }
    let(:pull_request_merged) { nil }

    def generate_github_event
      http.post "/github_handler" do |req|
        req.headers["X-GitHub-Event"] = event_type
        req.params[:payload] = {
          repository: {
            full_name: "chef/#{repository}",
          },
          action: pull_request_action,
          pull_request: {
            merged: pull_request_merged,
            url: "http://github.com/chef/#{repository}/pulls/2",
          },
        }.to_json
      end
    end

    context "for events other than pull-request" do
      let(:event_type) { "issues" }
      let(:repository) { "lita-test" }
      let(:pull_request_merged) { false }

      it "skips build" do
        expect_any_instance_of(Lita::Handlers::Versioner).not_to receive(:trigger_build)
        generate_github_event
      end
    end

    context "for unsupported projects" do
      let(:event_type) { "pull_request" }
      let(:repository) { "chef" }
      let(:pull_request_merged) { true }

      it "skips build" do
        expect_any_instance_of(Lita::Handlers::Versioner).not_to receive(:trigger_build)
        generate_github_event
      end
    end

    context "for pull-request events without merge" do
      let(:event_type) { "pull_request" }
      let(:repository) { "lita-test" }
      let(:pull_request_merged) { false }

      it "skips build" do
        expect_any_instance_of(Lita::Handlers::Versioner).not_to receive(:trigger_build)
        generate_github_event
      end
    end

    context "for merged pull-requests" do
      let(:event_type) { "pull_request" }
      let(:repository) { "lita-test" }
      let(:pull_request_merged) { true }

      it "skips build" do
        expect_any_instance_of(Lita::Handlers::Versioner).to receive(:bump_version_in_git)
        expect_any_instance_of(Lita::Handlers::Versioner).to receive(:trigger_build)
        generate_github_event
      end
    end
  end
end
