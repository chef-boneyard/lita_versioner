require "mixlib/shellout"
require "json"
require "uri"

module Lita
  class ProjectRepo
    class CommandError < StandardError; end

    CACHE_DIRECTORY = "./cache"

    attr_reader :github_url
    attr_reader :version_bump_command
    attr_reader :version_show_command
    attr_reader :dependency_update_command

    def initialize(project)
      @github_url = project[:github_url]
      @version_bump_command = project[:version_bump_command]
      @version_show_command = project[:version_show_command]
      @dependency_update_command = project[:dependency_update_command]
    end

    def bump_version
      return if version_bump_command.nil?

      Bundler.with_clean_env do
        run_command(version_bump_command)
      end
    end

    def update_dependencies
      if dependency_update_command.nil?
        raise CommandError,
          "Can not update deps for project '#{github_url}'; no dependency_update_command provided to initializer."
      end

      Bundler.with_clean_env do
        run_command(dependency_update_command)
      end
    end

    def read_version
      raise CommandError, "Can not read the version for project '#{github_url}'." if version_show_command.nil?

      Bundler.with_clean_env do
        run_command(version_show_command).stdout.chomp
      end
    end

    def tag_and_commit
      version = read_version

      ensure_git_config_set

      run_command("git add -A")
      run_command("git commit -m \"Bump version of #{repo_name} to #{version} by Chef Versioner.\"")
      run_command("git tag -a v#{version} -m \"Version tag for #{version}.\"")
      begin
        run_command("git push origin master --tags")
      rescue CommandError => e
        # We need to cleanup the local tag we have created if the push has failed.
        run_command("git tag -d v#{version}")
        raise e
      end
    end

    def force_commit_to_branch(branch_name)
      ensure_git_config_set
      run_command("git checkout -B #{branch_name}")
      run_command("git add -A")
      run_command("git commit -m \"Automatic dependency update by Chef Versioner\"")
      run_command("git push origin #{branch_name} --force")
    end

    # Clones the repo into cache or refreshes the repo in cache.
    def refresh
      ensure_cache_dir_exists

      if Dir.exists? repo_directory
        run_command("git fetch origin")
        run_command("git checkout -f master")
        run_command("git reset --hard origin/master")
        run_command("git clean -fdx")
      else
        run_command("git clone #{github_url}", cwd: File.dirname(repo_directory))
      end
    end

    # checks if there are any modified files that are tracked by git
    def has_modified_files?(compared_to_ref = "HEAD")
      !run_command("git diff #{compared_to_ref}").stdout.strip.empty?
    end

    def branch_exists?(branch_name)
      run_command("git rev-parse --verify #{branch_name}")
      true
    rescue CommandError
      false
    end

    def delete_branch(branch_name)
      run_command("git branch -D #{branch_name}")
      true
    rescue CommandError
      false
    end

    def has_file?(path_from_repo_root)
      File.exist?(File.join(repo_directory, path_from_repo_root))
    end

    # Time since the last commit on `git_ref` in seconds
    def time_since_last_commit_on(git_ref)
      now = Time.new.to_i
      commit_time = run_command("git show -s --format=\"%ct\" #{git_ref}").stdout.strip.to_i
      now - commit_time
    end

    def run_command(command, cwd: repo_directory)
      Lita.logger.info("Running command: '#{command}'")

      opts = {
        cwd: cwd,
        timeout: 3600,
      }

      opts[:live_stream] = $stdout if Lita.logger.debug?

      shellout = Mixlib::ShellOut.new(command, opts)
      shellout.run_command

      raise CommandError, [
        "Error running command '#{command}':",
        "stdout: #{shellout.stdout}",
        "stderr: #{shellout.stderr}",
      ].join("\n") if shellout.error?

      shellout
    end

    def repo_directory
      File.join(CACHE_DIRECTORY, repo_name)
    end

    def repo_name
      # Note that this matches github urls both like:
      #   https://github.com/litaio/development-environment.git
      #   git@github.com:chef-cookbooks/languages.git
      github_url.match(/.*\/(.*)\.git$/)[1]
    end

    def ensure_git_config_set
      if !run_command("git config -l").stdout.match(/chef-versioner@chef.io/)
        run_command("git config user.email \"chef-versioner@chef.io\"")
        run_command("git config user.name \"Chef Versioner\"")
      end
    end

    def ensure_cache_dir_exists
      Dir.mkdir(CACHE_DIRECTORY) unless File.exist? CACHE_DIRECTORY
    end

  end
end
