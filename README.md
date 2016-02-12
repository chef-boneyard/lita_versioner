# lita-versioner

[![Build Status](https://travis-ci.org/sersut/lita-versioner.png?branch=master)](https://travis-ci.org/sersut/lita-versioner)

TODO: Add a description of the plugin.

## Installation

Add lita-versioner to your Lita instance's Gemfile:

``` ruby
gem "lita-versioner"
```

## Configuration

TODO: Describe any configuration attributes the plugin exposes.

## Usage

TODO: Describe the plugin's features and how to use them.

## Development

### Github Connection

1. Install lita [development environment](http://docs.lita.io/getting-started/installation/#development-environment).
2. Install [ngrok](https://ngrok.com/download).
3. Launch ngrok inside the lita dev VM.
  * `./ngrok http 8080`
4. Add a webhook to your github repo per instructions [here](https://developer.github.com/guides/delivering-deployments/).
  * You can find the url you are looking for at https://dashboard.ngrok.com/status.
5. `bundle exec lita` from your lita dev VM.
