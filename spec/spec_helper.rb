require "lita_versioner"
require "lita/rspec"
require_relative "support/git_helpers"
require_relative "support/jenkins_helpers"
require_relative "support/lita_helpers"
require_relative "support/spec_helpers"

# A compatibility mode is provided for older plugins upgrading from Lita 3. Since this plugin
# was generated with Lita 4, the compatibility mode should be left disabled.
Lita.version_3_compatibility_mode = false

RSpec.configure do |config|
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
  config.include GitHelpers
  config.include JenkinsHelpers
  config.include SpecHelpers
end
