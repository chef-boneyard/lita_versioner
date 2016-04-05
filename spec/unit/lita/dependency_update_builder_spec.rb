require "spec_helper"
require "lita/dependency_update_builder"

RSpec.describe Lita::DependencyUpdateBuilder do

  let(:repo_url) { "git@github.com:chef/omnibus-harmony.git" }

  let(:dependency_bump_command) { "rake dependencies" }

  let(:dependency_branch) { "auto_dependency_bump_test" }

  subject(:dependency_update_builder) do
    described_class.new(repo_url: repo_url, dependency_branch: dependency_branch)
  end

  let(:logger) do
    double("Logger").tap do |l|
      allow(l).to receive(:info)
    end
  end

  before do
    allow(Lita).to receive(:logger).and_return(logger)
  end


  # synchronize_repo
  # stop if dont_bump_deps_file_present?
  # fetch_dep_updates
  # stop if no_deps_updated?
  # stop unless should_submit_changes_for_build?
  # submit_build

  it "has a project repo" do
    expect(dependency_update_builder.project_repo.github_url).to eq(repo_url)
  end

  context "with a correctly configured project repo" do

    let(:project_repo) { instance_double("Lita::ProjectRepo") }

    before do
      allow(dependency_update_builder).to receive(:project_repo).and_return(project_repo)
    end

    describe "synchronize_repo" do

      it "refreshes the project repo" do
        expect(project_repo).to receive(:refresh)
        dependency_update_builder.synchronize_repo
      end

    end

    context "when a 'don't bump deps' file is present" do

      before do
        allow(project_repo).to receive(:has_file?).
          with(".dependency_updates_disabled").
          and_return(true)
      end

      it "indicates that dependency bumping should be skipped" do
        expect(dependency_update_builder.dependency_updates_disabled?).to be(true)
      end

      it "does not run any dependency update or build steps" do
        expect(project_repo).to receive(:refresh)
        expect(dependency_update_builder.run).to be(false)
      end

    end

    context "when no 'don't bump deps' file is present" do

      before do
        allow(project_repo).to receive(:has_file?).
          with(".dependency_updates_disabled").
          and_return(false)
      end

      describe "update_dependencies" do

        it "runs the dependency update command" do
          expect(project_repo).to receive(:update_dependencies)
          dependency_update_builder.update_dependencies
        end

      end

      context "when no dependencies were updated" do

        before do
          allow(project_repo).to receive(:has_modified_files?).
            with(no_args).
            and_return(false)
        end

        it "indicates that no deps were updated" do
          expect(dependency_update_builder.dependencies_updated?).to be(false)
        end

        it "doesn't create a branch or start a build" do
          expect(project_repo).to receive(:refresh)
          expect(dependency_update_builder.run).to be(false)
        end
      end

      context "when dependencies were updated" do

        before do
          allow(project_repo).to receive(:has_modified_files?).
            with(no_args).
            and_return(true)
        end

        it "indicates that deps were updated" do
          expect(dependency_update_builder.dependencies_updated?).to be(true)
        end

        context "and there is no existing branch for dependency updates" do

          before do
            allow(project_repo).to receive(:branch_exists?).
              with("auto_dependency_bump_test").
              and_return(false)
          end

          it "indicates that a build should be submitted" do
            expect(dependency_update_builder.should_submit_changes_for_build?).to be(true)
          end

        end

        context "when the dependency update matches a previous build" do

          before do
            allow(project_repo).to receive(:branch_exists?).
              with("auto_dependency_bump_test").
              and_return(true)
            allow(project_repo).to receive(:has_modified_files?).
              with("auto_dependency_bump_test").
              and_return(false)
          end

          context "and the previous build is not more than FAILED_BUILD_QUIET_TIME old" do

            before do
              allow(project_repo).to receive(:time_since_last_commit_on).
                with("auto_dependency_bump_test").
                and_return(3600)
            end

            it "indicates that no build should be submitted" do
              expect(dependency_update_builder.should_submit_changes_for_build?).to be(false)
            end

            it "should not submit the changes for a new build" do
              expect(project_repo).to receive(:refresh)
              expect(dependency_update_builder.run).to be(false)
            end

          end

          context "but the previous build is more than FAILED_BUILD_QUIET_TIME old" do

            before do
              allow(project_repo).to receive(:time_since_last_commit_on).
                with("auto_dependency_bump_test").
                and_return(3600 * 25)
            end

            it "indicates that a build should be submitted" do
              expect(dependency_update_builder.should_submit_changes_for_build?).to be(true)
            end

            it "should submit the changes for a new build" do
              expect(project_repo).to receive(:refresh)
              expect(dependency_update_builder).to receive(:submit_build)
              expect(dependency_update_builder.run).to be(true)
            end

          end

        end

        context "when the dependency update does not match a previous build" do

          before do
            allow(project_repo).to receive(:branch_exists?).
              with("auto_dependency_bump_test").
              and_return(true)
            allow(project_repo).to receive(:has_modified_files?).
              with("auto_dependency_bump_test").
              and_return(true)
          end

          it "indicates that a build should be submitted" do
            expect(dependency_update_builder.should_submit_changes_for_build?).to be(true)
          end

          it "should submit the changes for new build" do
            expect(project_repo).to receive(:refresh)
            expect(dependency_update_builder).to receive(:submit_build)
            expect(dependency_update_builder.run).to be(true)
          end

        end

      end

      describe "submitting a build" do
        # commit_and_push
        # submit_jenkins_job
        # update_last_built_branch
      end

    end
  end
end
