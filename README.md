# lita-versioner

[![Build Status](https://travis-ci.org/chef/lita-versioner.png?branch=master)](https://travis-ci.org/chef/lita-versioner)

This plugin acts as a bridge between Github and Jenkins. When a pull request is merged in Github, `lita-versioner` automatically increases the version of the projects and triggers a Jenkins job.

## Configuration

| Parameter | Description |
|-----------|-------------|
| `jenkins_username` | Username for the Jenkins account to use when triggering jobs. |
| `jenkins_api_token` | Api token for the Jenkins account to use when triggering jobs. |

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

Configure a webhook for your Github repository following the instructions [here](https://developer.github.com/guides/delivering-deployments/). **Instead of selecting just the `push` event, select "Let me select individual events" and select only `pull request` events.

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

1. Create a PR setting the SHA in https://github.com/chef-cookbooks/oc-lita/blob/master/recipes/_plugin_versioner.rb to latest `master` of `lita-versioner` and bumping the version in `https://github.com/chef-cookbooks/oc-lita/blob/master/metadata.rb`.
2. Get a C/R, and have that person `@delivery approve` the PR.
3. If you are adding a repository, create or edit the github hook for that repository to point at the acceptance lita (example: https://github.com/chef/chef/settings/hooks/7767887). It should:
   - Payload URL: http://lita-relay-public-acceptance.chef.co/github_handler
   - Content type: application/x-www-form-urlencoded
   - Secret: <blank>
   - "Let me select individual events." and select only "Pull request" (deselect "Push").
4. Test it out by merging a PR to your repo.
5. If it's good, `@delivery deliver` the PR.
6. Update the above webhook to point at http://lita-relay-public.chef.co/github_handler

## Questions

You can ask your questions in `#engineering-services` or ping `@serdar` on Slack.

`Powered by Chef Engineering Services.`
