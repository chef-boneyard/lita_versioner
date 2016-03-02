require "spec_helper"

describe Lita::Handlers::Versioner, lita_handler: true do
  before do
    Lita.config.handlers.versioner.jenkins_username = "ci"
    Lita.config.handlers.versioner.jenkins_api_token = "ci_api_token"
  end

  it { is_expected.to route_command("build harmony").to(:build) }
  it { is_expected.to route_http(:post, "/github_handler").to(:github_handler) }

  it "does not build without project name" do
    expect(subject).not_to receive(:trigger_build)
    send_command("build")
    expect(replies.last).to match(/Argument issue./)
  end

  it "does not build unsupported projects" do
    expect(subject).not_to receive(:trigger_build)
    send_command("build chef")
    expect(replies.last).to match(/Project 'chef' is not supported./)
  end

  it "builds with master by default" do
    # lita-rspec is doing something with subject therefore we need expect_any_instance_of here.
    expect_any_instance_of(Lita::Handlers::Versioner).to receive(:trigger_build)
      .with("master").and_return(true)
    send_command("build harmony")
  end

  it "builds with the specified tag" do
    # lita-rspec is doing something with subject therefore we need expect_any_instance_of here.
    expect_any_instance_of(Lita::Handlers::Versioner).to receive(:trigger_build)
      .with("example").and_return(true)
    send_command("build harmony example")
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
            full_name: "chef/#{repository}"
          },
          action: pull_request_action,
          pull_request: {
            merged: pull_request_merged,
            url: "http://github.com/chef/#{repository}/pulls/2"
          }
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
