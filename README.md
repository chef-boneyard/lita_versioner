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

Configure a webhook for your Github repository following the instructions [here](https://developer.github.com/guides/delivering-deployments/).

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
6. Run lita within the lita development environment:
  * `bundle exec lita` from your lita dev VM.


## Questions

You can ask your questions in `#engineering-services` or ping `@serdar` on Slack.

`Powered by Chef Engineering Services.`
