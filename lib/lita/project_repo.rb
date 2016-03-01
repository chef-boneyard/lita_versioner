require "mixlib/shellout"
require "json"
require "uri"

module Lita
  class ProjectRepo
    class CommandError < StandardError; end

    CACHE_DIRECTORY = "./cache"

    attr_reader :github_url
    attr_reader :version_bump_command

    def initialize(github_url, version_bump_command = nil)
      @github_url = github_url
      @version_bump_command = version_bump_command

      Dir.mkdir(CACHE_DIRECTORY) unless File.exist? CACHE_DIRECTORY
    end

    def bump_version
      return if version_bump_command.nil?

      Bundler.with_clean_env do
        run_command(version_bump_command)
      end

      if !run_command("git config -l").stdout.match /lita-versioner@chef.io/
        run_command("git config user.email \"lita-versioner@chef.io\"")
        run_command("git config user.name \"Lita Versioner\"")
      end

      run_command("git add -A")
      run_command("git commit -m \"Automatic version bump for #{repo_name} by lita-versioner.\"")
      run_command("git push origin master")
    end

    # Clones the repo into cache or refreshes the repo in cache.
    def refresh
      if Dir.exists? repo_directory
        run_command("git reset --hard origin/master")
        run_command("git clean -fdx")
      else
        run_command("git clone #{github_url}", cwd: File.dirname(repo_directory))
      end
    end

    def run_command(command, cwd: repo_directory)
      shellout = Mixlib::ShellOut.new(
        command,
        cwd: cwd,
        timeout: 3600
      )
      shellout.run_command

      raise CommandError, [
        "Error running git command #{command}:",
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
