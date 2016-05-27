# lita_versioner

[![Build Status](https://travis-ci.org/chef/lita_versioner.png?branch=master)](https://travis-ci.org/chef/lita_versioner)

This plugin acts as a bridge between Github and Jenkins. When a pull request is merged in Github, `lita_versioner` automatically increases the version of the projects and triggers a Jenkins job.

The bot generally sits as @julia on slack.

## Triggers

There are a number of ways the bot triggers commands: Slack commands, incoming events, and periodic timers. This is a list.

### Slack Commands

The bot sits on various channels in slack (her name is @julia for the production lita and @dorothy for acceptance lita).

| Command                   | Description                                                      |
|---------------------------|------------------------------------------------------------------|
| `build PROJECT [GIT_REF]` | Triggers an ad-hoc build of the project, at the given SHA.       |
| `bump PROJECT`            | Bumps the patch version of project and triggers a release build. |
| `bump-deps PROJECT`       | Bumps all dependency versions of project and triggers an ad-hoc build. |

### Webpages and Event Handlers

The bot listens for various events and provides various webpages for status.  Production lita sits on http://lita-relay-public.chef.co/github_handler and acceptance lita sits on http://lita-relay-public-acceptance.chef.co/github_handler.

| Endpoint                 | Description                                                    |
|--------------------------|----------------------------------------------------------------|
| `/github_handler`          | A [Github hook](https://github.com/chef/chef/settings/hooks/7767887) sends [pull request events](https://developer.github.com/v3/activity/events/types/#pullrequestevent) to this handler. When it receives a PR merge, it runs the `bump PROJECT` command.

### Periodic Timers

Julia does some things on a schedule to make sure they get done.

| Command           | Description                                                        |
|-------------------|--------------------------------------------------------------------|
| Dependency Update | Every `polling_interval` minutes, runs `bump-deps` on each project |

## Functionality

Julia takes several distinct actions depending on what's going on:

### Build

When lita triggers a build, either via the `@julia build PROJECT [GIT_REF]` command, or a successful `@julia bump PROJECT`, `@julia bump-deps PROJECT`, or pull request merge, she triggers the build via the Jenkins API. It contacts the `jenkins_endpoint` using `jenkins_username` and `jenkins_api_token`, and uses the project's `pipeline`.

For example, it may send the POST request to http://manhattan.ci.chef.co/job/lita-test-trigger-release/buildWithParameters with the payload:

```
{ "GIT_REF" => "v1.2.0", "EXPIRE_CACHE" => false, "INITIATED_BY" => "BumpBot" })
```

### Version Bump

When lita is asked to bump the version of a pipeline either via the `@julia bump PROJECT` command or via a pull request being merged, she:

1. Clones/pulls the project from its `github_url`. This actually first updates the remote in a single central repository, and then `git clone`s *that* directory locally into a distinct copy for the version bump. It does this to avoid race conditions where multiple commands work on the same repository. The procedure:
   - `git clone --mirror <github_url> <cache_directory>/<repository_name>`
   - `git remote update` in `<cache_directory>/<repository_name>`
   - `git clone <cache_directory>/<repository_name> <sandbox_directory>/<handler_id>/<repository_name>`
   - `git remote set-url origin <github_url>` in `<sandbox_directory>/<handler_id>/<repository_name>`
2. Runs the pipeline's `version_bump_command` from the repository directory.
3. Runs the pipeline's `version_show_command` to get the version to report back.
4. Triggers a build via the release pipeline.

### Dependency Update

When lita is asked to update dependencies, either via `@julia bump-deps PROJECT` or on its periodic timer, it:

1. Clones/pulls the project from its `github_url`.
2. Runs the pipeline's `dependency_update_command` from the repository directory.
3. Triggers a build via the ad-hoc pipeline.

## Configuration

| Parameter | Description |
|-----------|-------------|
| `jenkins_username` | Username for the Jenkins account to use when triggering jobs. |
| `jenkins_api_token` | Api token for the Jenkins account to use when triggering jobs. |
| `jenkins_endpoint` | Endpoint for jenkins, e.g. http://manhattan.ci.chef.co/ |
| `polling_interval` | How often to check for dependency updates on each pipeline |
| `trigger_real_builds` | Set true to actually trigger builds when asked. False if not. Used for testing. |
| `default_inform_channel` | Channel to inform when we don't know where to send a message. e.g. `chef-notify` |
| `projects` | Hash of pipeline name -> project configuration. See Project Configuration below.
| `cache_directory` | Cache directory for data that can persist but may be safely removed (e.g. clones of git) |
| `sandbox_directory` | Directory where individual commands can store data temporarily. These directories are kept around when a command fails. |
| `debug_lines_in_pm` | Set false if you don't want debug lines sent in private messages by default. |

### Project Configuration

Projects are configured like:

```
projects = {
  "chef" => {
    pipeline: "chef-trigger-release",
    github_url: "https://github.com/chef/chef.git",
    version_bump_command: "bundle install && bundle exec rake version:bump && git checkout .bundle/config",
    version_show_command: "bundle exec rake version:show",
    dependency_update_command: "bundle install && bundle exec rake dependencies && git checkout .bundle/config",
    inform_channel: "workflow-pool",
  }
}
```

| Parameter                   | Description                                                   |
|-----------------------------|---------------------------------------------------------------|
| `pipeline`                  | Release pipeline for job.                                     |
| `github_url`                | Github remote URL for cloning and github events.              |
| `version_bump_command`      | Command to run to bump the patch version of the project. Run when pull requests are merged and when `@julia bump PROJECT` command is invoked. |
| `version_show_command`      | Command to run to show the version of the project. Run when pull requests are merged and when `@julia bump PROJECT` command is invoked. |
| `dependency_update_command` | Command to run to update dependencies for the project. Run when `@julia bump-deps PROJECT` happens and on a timer schedule. |
| `inform_channel`            | The channel where statuses for this pipeline should be sent. |

## Usage

Update the `config :projects` defined in `lib/lita/handlers/versioner.rb` with the required information. E.g:

```
harmony: {
  pipeline: "harmony-trigger-ad_hoc",
  repository: "opscode-harmony"
},
# project_name: {
#   pipeline: "name of the Jenkins job to trigger",
#   repository: "name of the Github repo to monitor"
# }
```

Configure a webhook for your Github repository following the instructions [here](https://developer.github.com/guides/delivering-deployments/). **Instead of selecting just the `push` event, select "Let me select individual events" and select only `pull request` events.**

## Development

Lita has great documentation. Read [this](http://docs.lita.io/plugin-authoring/) first before starting. It will make below instructions easy to understand.

### First Time Setup

1. Install [Docker Toolbox](https://www.docker.com/products/docker-toolbox):
   - `brew cask install dockertoolbox`
   - `docker-machine create default --driver virtualbox`
   - `eval $(docker-machine env default)` <-- you might want that in your .profile
2. Copy `lita_config.rb.example` to `lita_config.rb`.

NOTE: this will let you work with github, but won't talk to Slack, Jenkins or receive Github notifications by default--see later configuration sections for those.

### Running Lita

To run lita, do:

```
docker/run
```

You should see this towards the end:

```
Type "exit" or "quit" to end the session.
Lita >
```

From here you can interact with the bot just like on Slack. Type `@lita help` for a list of commands.
Note that the default docker/run command mounts your home directory at the container's ~lita. Hence,
lita will performs actions using your ssh credentials unless they are encrypted private keys.

### Testing Against Slack

To test that the bot can communicate on Slack, you need to set up the bot and join it to the channel:

1. Set up the bot on Slack.
   - Go to the [new Lita bot page](https://chefio.slack.com/apps/new/A0F7XDUJH-lita) on Slack.
   - Create a username, like `<YOUR USERNAME>-testbot`.
   - Copy the Slack token.
2. Set up a channel for testing and invite your bot to it.
   - /join #<YOUR USERNAME>-testbot
   - /invite @<YOUR USERNAME>-testbot
3. Configure the bot locally.
   - Bring over the lita_config.rb.example slack configuration, inserting the token from step 1 and choosing a channel:

     ```ruby
     config.adapters.slack.token = "<MY API TOKEN>"
     config.adapters.slack.link_names = true
     config.adapters.slack.parse = "full"
     config.adapters.slack.unfurl_links = false
     config.adapters.slack.unfurl_media = false
     config.default_inform_channel = "#<MY TEST CHANNEL>"
     ```

Now when you start the bot, it should join!

### Testing Against Jenkins

To test against Jenkins, you just need to add the correct tokens to the config file.

1. Get your Jenkins API token by logging in to https://manhattan.ci.chef.co, clicking your name on the top right, and clicking Configure. Then click "Show API Token" and copy the values for the next step.
2. Edit `lita_config.rb` to add the two jenkins lines below:

   ```ruby
   Lita.configure do |config|
     # Add these two lines:
     config.handlers.versioner.jenkins_username = "YOUR JENKINS USERNAME"
     config.handlers.versioner.jenkins_api_token = "YOUR TOKEN FROM STEP 1"
     ........
   end
   ```

`docker/run` and you should be set up!

### Testing Github Hooks

To test github hooks, we're going to use ngrok:

1. Log in to the [ngrok Auth tab](https://dashboard.ngrok.com/auth).
2. Put your auth token in ``~/.ngrok2/ngrok.yml`:

   ```yaml
   authtoken: <YOUR AUTH TOKEN>
   ```
3. `docker/run-ngrok`

Note the URL it gives you.

To test that the version bumper correctly listens to github hooks, set up a github hook in your repository just like the Updating the Bot section, but replace the URL with the ngrok URL. e.g. `http://d9ca4a7a.ngrok.io/github_handler`

## Updating the Bot

To update the bot, you've one more thing to do: Deliver!

1. Create a PR setting the SHA in https://github.com/chef-cookbooks/oc-lita/blob/master/recipes/_plugin_versioner.rb to latest `master` of `lita_versioner` and bumping the version in `https://github.com/chef-cookbooks/oc-lita/blob/master/metadata.rb`.
2. Get a C/R, and have that person `@delivery approve` the PR.
3. If you are adding a repository, create or edit the github hook for that repository to point at the acceptance lita (example: https://github.com/chef/chef/settings/hooks/7767887). It should:
   - Payload URL: http://lita-relay-public-acceptance.chef.co/github_handler
   - Content type: application/x-www-form-urlencoded
   - Secret: <blank>
   - "Let me select individual events." and select only "Pull request" (deselect "Push").
4. Test it out by merging a PR to your repo.
5. If it's good, `@delivery deliver` the PR.
6. Update the above webhook to point at http://lita-relay-public.chef.co/github_handler

## Future Plans

Here are things that need doing to make the bot more effective:

### Message Sanity

- Reduce volume and size of messages to channel
  - Do not send "starting to process" notifications to channel (only failure/success)
  - Do not send success notifications to channel unless it's a change or it's been N hours
  - Send large outputs (such as error output) as attachments
- Query julia for more detailed logs
  - "julia pipeline commands in progress" to show commands in progress
  - "julia pipeline commands" to show recent commands and their status
  - "julia pipeline command output <number> [debug|info|warn|error]" to show output for a command (will attach to its stdout if it's in progress). Default: debug if pm, info if channel

### Operability

- "julia pipeline version" to show lita_versioner version (and git SHA if applicable, with link to github)
- "julia pipeline config [a.b.c]" to show configuration (scrub secrets like tokens)
- "julia pipeline set config a.b.c [value]" to set configuration (stored in redis, overlaid on top of config). Add projects, set project pipeline info this way.
- "julia pipeline reset config a.b.c" to reset configuration (and projects) to their default. Shows the old value so you can set it if you need to.

### Pipeline Status

As goalie, the most important thing to know is whether the pipeline is working or not. Julia has access to all of this information and we've written all the code we need to do it. We can use https://github.com/jkeiser/jenkins_report to summarize build status for easy understanding of root causes.

To this end, we should create a webpage on julia (i.e. http://lita-relay-public.chef.co/pipelines/chef/status) that we can hit to look at the status for each pipeline. A "julia pipeline status PROJECT" command would show the top level status (green+red, a little explanation, and a link). Julia would send notifications to a pipeline's channel when status of a pipeline changes.

We'd start small, but the report in its fullness could include:

- Status of master:
  - Latest version on master, latest checkin to master.
  - Latest successful/completed/in progress release build version, julia log, build link, package links, and status summary.
  - Latest successful/completed/in progress Julia bump attempt (same info).
  - Github webhook status (github API to https://github.com/chef/chef/settings/hooks/7767887).
  - Red if last bump attempt failed, if master is not a version bump (and no in progres attempt), or if github webhook is not live and pointing to us.

- Status of dependency update:
  - Latest successful/completed/in progress dependency build julia log, build link, package links, and status summary.
  - Latest successful/completed/in progress Julia dependency update attempt (same info)
  - Red if latest dependency update failed or dependency update has not run in the past N hours

- Slack status:
  - Whether it is connected to slack
  - List of channels it's joined

- Jenkins pipeline status:
  - Status of builders in our project
  - Status of queues (in progress, waiting)
  - Most recent successful/completed/in progress builds with julia log (if applicable), build link, package links, and status summary, across *all* triggers, including ad_hoc.
  - Red if any job has waited for more than an hour, or if Jenkins is down, or if any set of slaves is completely offline.

#### Github Integration

To make it easier to see the status of PRs and of master, we should add github statuses and use PRs where appropriate.

- Create an actual PR when dependencies are updated and merge that rather than committing directly
- Record git status of any build via https://developer.github.com/v3/repos/statuses/
- Record git status of any version bump or dependency update attempt via https://developer.github.com/v3/repos/statuses/
- Store build summary in either git status or jenkins
- Make it easier to trawl the webhook event logs:
  - 404 response from github handler when we skip a build so we can trawl the github event logs better (i.e. https://github.com/chef/chef/settings/hooks/7767887)
  - report the reason we skipped each build via github handler so we can investigate if something seems wrong.

### Misc

- Automatically merge dependency update build.
- Display the actual build link when triggering a build.

## Questions

You can ask your questions in `#engineering-services` or ping `@serdar` on Slack.

`Powered by Chef Engineering Services.`
