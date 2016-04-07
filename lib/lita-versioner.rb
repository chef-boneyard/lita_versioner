require "lita"

Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

require "lita/handlers/versioner"
require "lita/handlers/dependency_updater"

Lita::Handlers::Versioner.template_root File.expand_path(
  File.join("..", "..", "templates"),
 __FILE__
)
