# lita-versioner

[![Build Status](https://travis-ci.org/sersut/lita-versioner.png?branch=master)](https://travis-ci.org/sersut/lita-versioner)

This plugin acts as a bridge between Github & Jenkins. When a pull request is merged in Github, `lita-versioner` automatically increases the version of the projects and triggers a Jenkins job.

## Configuration

| Parameter | Description |
|-----------|-------------|
| `jenkins_username` | Username for the Jenkins account to use when triggering jobs. |
| `jenkins_api_token` | Api token for the Jenkins account to use when triggering jobs. |

## Usage

Update the `PROJECTS` defined in `Lita::Handlers::Versioner` with the required information. E.g:

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

1. Install and start [lita development environment](http://docs.lita.io/getting-started/installation/#development-environment).
2. Inside the lita development environment:
  1. Install [ngrok](https://ngrok.com/download).
  2. Launch ngrok inside the lita dev VM.
    * `./ngrok http 8080`
  3. Follow instructions [here](https://dashboard.ngrok.com/get-started) to setup ngrok.
3. Add a webhook to your github repo per instructions [here](https://developer.github.com/guides/delivering-deployments/).
  * You can find the ngrok url to use at [ngrok dashboard](https://dashboard.ngrok.com/status).
4. Copy the github key you would like to use into `/home/lita/.ssh/github` with mod `0600`.
5. Create `/home/lita/.ssh/config` to use the correct key when talking to Github:
  ```
  Host github.com
  IdentityFile /home/lita/.ssh/github
  StrictHostKeyChecking no
  ```
6. Install git: `apt-get install git`
7. Put `lita-versioner` into `lita-dev/workspace`.
8. Get your Jenkins API token by logging in to https://manhattan.ci.chef.co, clicking your name on the top right, and clicking Configure. Then click "Show API Token" and copy the values for the next step.
9. Create `lita-versioner/lita_config.rb` with this text:
   ```ruby
   Lita.configure do |config|
     config.handlers.versioner.jenkins_username = "YOUR USERNAME"
     config.handlers.versioner.jenkins_api_token = "YOUR TOKEN"
     config.robot.adapter = :shell
     config.robot.log_level = :debug
   end
   ```
10. Run lita within the lita development environment:
  * `bundle exec lita` from `workspace/lita-versioner` on your lita dev VM.
  * You should see this:
    ```
    Type "exit" or "quit" to end the session.
    Lita >
    ```
  * From here you can interact with the bot just like on Slack.

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
