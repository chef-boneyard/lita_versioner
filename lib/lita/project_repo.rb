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

    def initialize(project)
      @github_url = project[:github_url]
      @version_bump_command = project[:version_bump_command]
      @version_show_command = project[:version_show_command]

      Dir.mkdir(CACHE_DIRECTORY) unless File.exist? CACHE_DIRECTORY
    end

    def bump_version
      return if version_bump_command.nil?

      Bundler.with_clean_env do
        run_command(version_bump_command)
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

      if !run_command("git config -l").stdout.match /chef-versioner@chef.io/
        run_command("git config user.email \"chef-versioner@chef.io\"")
        run_command("git config user.name \"Chef Versioner\"")
      end

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

    # Clones the repo into cache or refreshes the repo in cache.
    def refresh
      if Dir.exists? repo_directory
        run_command("git fetch origin")
        run_command("git reset --hard origin/master")
        run_command("git clean -fdx")
      else
        run_command("git clone #{github_url}", cwd: File.dirname(repo_directory))
      end
    end

    def run_command(command, cwd: repo_directory)
      Lita.logger.info("Running command: '#{command}'")
      shellout = Mixlib::ShellOut.new(
        command,
        cwd: cwd,
        timeout: 3600
      )
      shellout.run_command

      raise CommandError, [
        "Error running command '#{command}':",
        "stdout: #{shellout.stdout}",
        "stderr: #{shellout.stderr}"
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
  end
end
