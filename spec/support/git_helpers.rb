require "tmpdir"
require "mixlib/shellout"
require "fileutils"

module GitHelpers
  def tmpdir
    @tmpdir ||= Dir.mktmpdir("lita_versioner")
  end

  def shellout!(command, options = {})
    cmd = Mixlib::ShellOut.new(command, options)
    cmd.environment["HOME"] = "/tmp" unless ENV["HOME"]
    cmd.run_command
    cmd
  end

  def create_remote_git_repo(remote_path, files)
    # Create a bogus software
    FileUtils.mkdir_p(remote_path)

    Dir.chdir(remote_path) do
      git %{init --bare}
      git %{config core.sharedrepository 1}
      git %{config receive.denyCurrentBranch ignore}
    end

    # Push initial commit there
    commit_dir = Dir.mktmpdir
    begin
      FileUtils.mkdir_p(commit_dir)
      Dir.chdir(commit_dir) do
        files.each do |file, content|
          IO.write(file, content)
        end
        git %{init .}
        git %{add --all}
        git %{commit -am "Initial commit"}
        git %{remote add origin "#{remote_path}"}
        git %{push origin master}
      end
    ensure
      FileUtils.remove_entry(commit_dir)
    end
  end

  def with_clone(remote_path)
    # Push initial commit there
    commit_dir = Dir.mktmpdir
    begin
      FileUtils.mkdir_p(File.dirname(commit_dir))
      git %{clone #{remote_path} #{commit_dir}}

      Dir.chdir(commit_dir) do
        yield commit_dir
      end

    ensure
      FileUtils.remove_entry(commit_dir)
    end
  end

  def create_commit(remote_path, files)
    with_clone(remote_path) do
      files.each do |file, content|
        IO.write(file, content)
      end
      git %{add --all}
      git %{commit -am "Another commit"}
      git %{push}
    end

    git_sha(remote_path)
  end

  # Calculate the git sha for the given ref.
  #
  # @param [#to_s] path
  #   the repository to show the ref for
  # @param [#to_s] ref
  #   the ref to show
  #
  # @return [String]
  def git_sha(path, ref: "master")
    Dir.chdir(path) do
      git("show-ref #{ref}").stdout.split(/\s/).first
    end
  end

  def git_file(path, file, ref: "master")
    Dir.chdir(path) do
      git("show #{ref}:#{file}").stdout
    end
  end

  private

  def git(command)
    #
    # We need to override some of the variable's git uses for generating
    # the SHASUM for testing purposes
    #
    time = Time.at(680227200).utc.strftime("%c %z")
    env  = {
      "GIT_AUTHOR_NAME"     => "omnibus",
      "GIT_AUTHOR_EMAIL"    => "omnibus@getchef.com",
      "GIT_AUTHOR_DATE"     => time,
      "GIT_COMMITTER_NAME"  => "omnibus",
      "GIT_COMMITTER_EMAIL" => "omnibus@gechef.com",
      "GIT_COMMITTER_DATE"  => time,
    }

    shellout!("git #{command}", env: env)
  end
end
