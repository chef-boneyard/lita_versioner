require "mixlib/shellout"
require "json"
require "uri"

module LitaVersioner
  class ProjectRepo
    class CommandError < StandardError; end

    #
    # Attributes
    #
    attr_reader :handler

    def project
      handler.project
    end

    def github_url
      project[:github_url]
    end

    def version_bump_command
      project[:version_bump_command]
    end

    def version_show_command
      project[:version_show_command]
    end

    def dependency_update_command
      project[:dependency_update_command]
    end

    def main_repo_directory
      File.join(handler.config.cache_directory, repo_name)
    end

    def repo_directory
      File.join(handler.sandbox_directory, repo_name)
    end

    #
    # Initializer
    #
    def initialize(handler)
      @handler = handler
      clone
    end

    #
    # Primary Commands
    #

    def bump_version
      return if version_bump_command.nil?

      run_command(version_bump_command)
    end

    def update_dependencies
      if dependency_update_command.nil?
        raise CommandError,
          "Can not update deps for project '#{github_url}'; no dependency_update_command provided to initializer."
      end

      run_command(dependency_update_command)
    end

    def read_version
      raise CommandError, "Can not read the version for project '#{github_url}'." if version_show_command.nil?

      run_command(version_show_command).stdout.chomp
    end

    def tag_and_commit
      version = read_version
      tag = "v#{version}"

      ensure_git_config_set

      run_command(%w{git add -A})
      run_command(%w{git commit -m} + ["Bump version of #{repo_name} to #{version} by Chef Versioner."])
      run_command(%W{git tag -a #{tag} -m} + ["Version tag for #{version}."])
      begin
        run_command(%w{git push origin master --tags})
        tag
      rescue
        # We need to cleanup the local tag we have created if the push has failed.
        run_command(%W{git tag -d #{tag}})
        raise
      end
    end

    def force_commit_to_branch(branch_name)
      ensure_git_config_set
      run_command(%W{git checkout -B #{branch_name}})
      run_command(%w{git add -A})
      run_command(%w{git commit -m } + [ "Automatic dependency update by Chef Versioner" ])
      run_command(%W{git push origin #{branch_name} --force})
    end

    # checks if there are any modified files that are tracked by git
    def has_modified_files?(compared_to_ref = "HEAD")
      !run_command(%W{git diff #{compared_to_ref}}).stdout.strip.empty?
    end

    def branch_exists?(branch_name)
      run_command(%W{git rev-parse --verify #{branch_name}})
      true
    rescue Mixlib::ShellOut::ShellCommandFailed
      false
    end

    def delete_branch(branch_name)
      run_command(%W{git branch -D #{branch_name}})
      true
    rescue Mixlib::ShellOut::ShellCommandFailed
      false
    end

    def has_file?(path_from_repo_root)
      File.exist?(File.join(repo_directory, path_from_repo_root))
    end

    # Time since the last commit on `git_ref` in seconds
    def time_since_last_commit_on(git_ref)
      now = Time.new.to_i
      commit_time = run_command(%W{git show -s --format=\"%ct\" #{git_ref}}).stdout.strip.to_i
      now - commit_time
    end

    def current_sha
      run_command(%w{git show-ref master}).stdout.split(/\s/).first
    end

    def run_command(command, cwd: repo_directory)
      handler.run_command(command, cwd: cwd)
    end

    def repo_name
      # Note that this matches github urls both like:
      #   https://github.com/litaio/development-environment.git
      #   git@github.com:chef-cookbooks/languages.git
      #   /tmp/lita-test
      repo = File.basename(github_url)
      repo = repo[0..-5] if repo.end_with?(".git")
      repo
    end

    def ensure_git_config_set
      if !run_command(%w{git config -l}).stdout.match(/chef-versioner@chef.io/)
        run_command(%w{git config user.email chef-versioner@chef.io})
        run_command(%w{git config user.name} + [ "Chef Versioner" ])
      end
    end

    def ensure_cache_dir_exists
      Dir.mkdir(CACHE_DIRECTORY) unless File.exist? CACHE_DIRECTORY
    end

    private

    # Clone ./cache/chef-dk.git into ./cache/<handler.id>/chef-dk
    def clone
      # Grab ./cache/chef-dk.git.
      refresh_main_repository

      # Ensure ./cache/<handler.id>/chef-dk does *not* exist.
      FileUtils.rm_rf(repo_directory)

      # Clone ./cache/chef-dk.git into ./cache/<handler.id>/chef-dk
      run_command(%W{git clone #{main_repo_directory} #{repo_directory}}, cwd: File.dirname(repo_directory))
      run_command(%W{git remote set-url origin #{github_url}})
    end

    @@main_repo_mutex = Mutex.new
    def main_repo_mutex
      @@main_repo_mutex
    end

    # Create or refresh ./cache/chef-dk.git
    def refresh_main_repository
      main_repo_mutex.synchronize do
        # Clone the main repository if it doesn't exist
        unless Dir.exists?(main_repo_directory)
          FileUtils.mkdir_p(File.dirname(main_repo_directory))
          run_command(%W{git clone --mirror #{github_url} #{main_repo_directory}}, cwd: File.dirname(main_repo_directory))
        end
        # Update remotes
        run_command(%w{git remote update}, cwd: main_repo_directory)
      end
    end
  end
end
