require "lita"
Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

require_relative "lita_versioner/version"
require_relative "lita/handlers/versioner"
require_relative "lita/handlers/dependency_updater"
require_relative "lita/handlers/bumpbot_status_handler"
require_relative "lita/handlers/bumpbot_status_webpage_handler"
