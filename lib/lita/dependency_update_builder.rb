require "lita/project_repo"

module Lita
  class DependencyUpdateBuilder

    # This is the number of seconds to wait before re-submitting a build that
    # is unchanged from the last one we submitted.
    #
    # When the build fails after updating dependencies, it could be caused
    # either by the dependency updates (i.e., a bug) or some kind of
    # intermittent issue in the build (network failure, upstream service is
    # down, etc.). Therefore we *do* want to retry the build, but we want to
    # rate-limit so we're not spamming the build system with something that can
    # never work.
    QUIET_TIME_S = 24 * 60 * 60

    attr_reader :handler
    attr_reader :dependency_branch

    def initialize(handler:, dependency_branch:)
      @handler = handler
      @dependency_branch = dependency_branch
    end

    def project_repo
      @repo ||= ProjectRepo.new(handler)
    end

    def run
      synchronize_repo
      if dependency_updates_disabled?
        message = "dependency updates disabled, skipping"
        handler.info(message)
        return [ false, message ]
      end

      update_dependencies

      unless dependencies_updated?
        message = "dependencies on master are up to date"
        handler.info(message)
        return [ false, message ]
      end

      unless should_submit_changes_for_build?
        message = "dependency changes failed a previous build. waiting for the quiet period to expire before building again"
        handler.info(message)
        return [ false, message ]
      end

      push_changes_to_upstream

      [ true, "dependency updates pushed to #{dependency_branch}" ]
    end

    def synchronize_repo
      project_repo.refresh
    end

    def dependency_updates_disabled?
      project_repo.has_file?(".dependency_updates_disabled")
    end

    def update_dependencies
      project_repo.update_dependencies
    end

    def dependencies_updated?
      project_repo.has_modified_files?
    end

    def should_submit_changes_for_build?
      return true unless project_repo.branch_exists?(dependency_branch)

      return true if project_repo.has_modified_files?(dependency_branch)

      return true if project_repo.time_since_last_commit_on(dependency_branch) > QUIET_TIME_S

      false
    end

    def push_changes_to_upstream
      project_repo.force_commit_to_branch(dependency_branch)
    end

  end
end
