require "spec_helper"
require "tmpdir"
require "fileutils"

describe Lita::Handlers::DependencyUpdater, lita_handler: true, additional_lita_handlers: Lita::Handlers::BumpbotHandler do
  # Initialize lita
  before do
    Lita.config.handlers.versioner.projects = {
      "lita-test" => {
        pipeline: "lita-test-trigger-ad_hoc",
        github_url: git_remote,
        version_bump_command: "cat a.txt >> file.txt",
        version_show_command: "cat file.txt",
        dependency_update_command: "cat a.txt > deps.txt",
        inform_channel: "notifications",
      },
    }
  end

  context "update dependencies" do
    #
    # Bad arguments
    #
    context "bad arguments" do
      it "update dependencies with no arguments emits a reasonable error message" do
        send_command("update dependencies")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** No project specified!
          Usage: update dependencies PROJECT   - Runs the dependency updater and submits a build if there are new dependencies.
        EOM
      end

      it "update dependencies blarghle emits a reasonable error message" do
        send_command("update dependencies blarghle")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** Invalid project blarghle. Valid projects: lita-test.
          Usage: update dependencies PROJECT   - Runs the dependency updater and submits a build if there are new dependencies.
        EOM
      end

      it "update dependencies lita-test blarghle does not update (too many arguments)" do
        send_command("update dependencies lita-test blarghle")

        expect(reply_string).to eq(strip_eom_block(<<-EOM))
          **ERROR:** Too many arguments (2 for 1)!
          Usage: update dependencies PROJECT   - Runs the dependency updater and submits a build if there are new dependencies.
        EOM
      end
    end

    #
    # Git repo
    #
    let(:git_remote) { File.join(tmpdir, "lita-test") }

    context "with a git repository containing a.txt=A and deps.txt=Y" do
      # Create a repository with file.txt = A, deps.txt=X
      attr_reader :initial_commit_sha
      before do
        create_remote_git_repo(git_remote, "a.txt" => "A", "deps.txt" => "Y")
        @initial_commit_sha = git_sha(git_remote)
      end

      context "when the dependency branch exists" do
        before do
          with_clone(git_remote) do
            git %{checkout -B auto_dependency_bump_test}
            git %{push -u origin auto_dependency_bump_test}
          end
        end

        #
        # Jenkins
        #
        with_jenkins_server "http://manhattan.ci.chef.co" do
          context "when no bumpbot builds have ever been triggered" do
            jenkins_data "jobs" => {
              "lita-test-trigger-ad_hoc" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
              "lita-test-build" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
              "lita-test-test" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
              "lita-test-release" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
            }

            it "update dependencies lita-test updates dependencies" do
              expect_jenkins_build("/job/lita-test-trigger-ad_hoc", git_ref: "auto_dependency_bump_test", initiated_by: "Test User")

              send_command("update dependencies lita-test")

              expect(reply_string).to eq(strip_eom_block(<<-EOM))
                Checking for updated dependencies for lita-test...
                Started dependency update build for project lita-test.
                Diff: https://github.com/chef/lita-test/compare/auto_dependency_bump_test
              EOM

              expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("A")
            end

            context "and there are no updates to make" do
              before do
                create_commit(git_remote, { "deps.txt" => "A" })
              end

              it "update dependencies lita-test does not update" do
                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  dependencies on master are up to date
                  **ERROR:** Dependency update build not triggered: dependencies on master are up to date
                EOM
                expect(git_file(git_remote, "deps.txt")).to eq("A")
              end
            end

            context "when the dependency branch is out of date with respect to master" do
              it "update dependencies lita-test updates dependencies" do
                expect_jenkins_build("/job/lita-test-trigger-ad_hoc", git_ref: "auto_dependency_bump_test", initiated_by: "Test User")

                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  Started dependency update build for project lita-test.
                  Diff: https://github.com/chef/lita-test/compare/auto_dependency_bump_test
                EOM

                expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("A")
              end
            end
          end

          context "when no builds have ever been triggered" do
            jenkins_data "jobs" => {
              "lita-test-trigger-ad_hoc" => [
              ],
              "lita-test-build" => [
              ],
              "lita-test-test" => [
              ],
              "lita-test-release" => [
              ],
            }

            it "update dependencies lita-test updates dependencies" do
              expect_jenkins_build("/job/lita-test-trigger-ad_hoc", git_ref: "auto_dependency_bump_test", initiated_by: "Test User")

              send_command("update dependencies lita-test")

              expect(reply_string).to eq(strip_eom_block(<<-EOM))
                Checking for updated dependencies for lita-test...
                Started dependency update build for project lita-test.
                Diff: https://github.com/chef/lita-test/compare/auto_dependency_bump_test
              EOM

              expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("A")
            end
          end

          context "when the most recent bumpbot build succeeded" do
            jenkins_data "jobs" => {
              "lita-test-trigger-ad_hoc" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
              ],
              "lita-test-build" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
              ],
              "lita-test-test" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
              ],
              "lita-test-release" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
              ],
            }

            it "update dependencies lita-test updates dependencies" do
              expect_jenkins_build("/job/lita-test-trigger-ad_hoc", git_ref: "auto_dependency_bump_test", initiated_by: "Test User")

              send_command("update dependencies lita-test")

              expect(reply_string).to eq(strip_eom_block(<<-EOM))
                Checking for updated dependencies for lita-test...
                Started dependency update build for project lita-test.
                Diff: https://github.com/chef/lita-test/compare/auto_dependency_bump_test
              EOM

              expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("A")
            end
          end

          context "in progress" do
            context "when a non-bumpbot build is in progress" do
              jenkins_data "jobs" => {
                "lita-test-trigger-ad_hoc" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-build" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => nil,       parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-test" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-release" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
              }

              it "update dependencies lita-test does not update" do
                expect_jenkins_build("/job/lita-test-trigger-ad_hoc", git_ref: "auto_dependency_bump_test", initiated_by: "Test User")

                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  Started dependency update build for project lita-test.
                  Diff: https://github.com/chef/lita-test/compare/auto_dependency_bump_test
                EOM

                expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("A")
              end
            end

            context "when the most recent bumpbot is in progress in release" do
              jenkins_data "jobs" => {
                "lita-test-trigger-ad_hoc" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-build" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-test" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-release" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => nil,       parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
              }

              it "update dependencies lita-test updates dependencies" do
                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  WARN: Dependency update build not triggered: conflicting build in progress.
                EOM
                expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("Y")
              end
            end

            context "when the most recent bumpbot build is in progress in test" do
              jenkins_data "jobs" => {
                "lita-test-trigger-ad_hoc" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-build" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-test" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => nil,       parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-release" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
              }

              it "update dependencies lita-test does not update" do
                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  WARN: Dependency update build not triggered: conflicting build in progress.
                EOM
                expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("Y")
              end
            end

            context "when the most recent bumpbot build is in progress in build" do
              jenkins_data "jobs" => {
                "lita-test-trigger-ad_hoc" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-build" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => nil,       parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-test" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-release" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
              }

              it "update dependencies lita-test does not update" do
                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  WARN: Dependency update build not triggered: conflicting build in progress.
                EOM
                expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("Y")
              end
            end

            context "when the most recent bumpbot build is in progress in trigger" do
              jenkins_data "jobs" => {
                "lita-test-trigger-ad_hoc" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => nil,       parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                ],
                "lita-test-build" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-test" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-release" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
              }

              it "update dependencies lita-test does not update" do
                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  WARN: Dependency update build not triggered: conflicting build in progress.
                EOM
                expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("Y")
              end
            end

            context "when the most recent bumpbot build is in progress, but the most recent build overall is *not* in progress" do
              jenkins_data "jobs" => {
                "lita-test-trigger-ad_hoc" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-build" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => nil,       parameters: { "GIT_REF" => "auto_dependency_bump_test" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-test" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
                "lita-test-release" => [
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                  { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
                ],
              }

              it "update dependencies lita-test does not update" do
                send_command("update dependencies lita-test")

                expect(reply_string).to eq(strip_eom_block(<<-EOM))
                  Checking for updated dependencies for lita-test...
                  WARN: Dependency update build not triggered: conflicting build in progress.
                EOM
                expect(git_file(git_remote, "deps.txt", ref: "auto_dependency_bump_test")).to eq("Y")
              end
            end
          end
        end
      end

      context "when the dependency branch does not exist" do
        with_jenkins_server "http://manhattan.ci.chef.co" do
          context "when no bumpbot builds have ever been triggered" do
            jenkins_data "jobs" => {
              "lita-test-trigger-ad_hoc" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
              "lita-test-build" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
              "lita-test-test" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
              "lita-test-release" => [
                { "result" => "SUCCESS", parameters: { "GIT_REF" => "master" } },
              ],
            }

            it "update dependencies lita-test updates dependencies" do
              expect_jenkins_build("/job/lita-test-trigger-ad_hoc", git_ref: "auto_dependency_bump_test", initiated_by: "Test User")

              send_command("update dependencies lita-test")

              expect(reply_string).to eq(strip_eom_block(<<-EOM))
                Checking for updated dependencies for lita-test...
                Started dependency update build for project lita-test.
                Diff: https://github.com/chef/lita-test/compare/auto_dependency_bump_test
              EOM
            end
          end
        end
      end
    end
  end
end
