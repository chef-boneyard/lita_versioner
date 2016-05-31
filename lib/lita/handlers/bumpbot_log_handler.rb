module Lita
  module Handlers
    class BumpbotHandler < Handler
      command_route(
        "pipeline active handlers",
        "Shows all active handlers",
      ) do
      end

      command_route(
        "pipeline show",
        { "HANDLER_ID [debug|info|warn|error]" => "Show the output of a given handler" }
        project_arg: false
      ) do |handler_id, log_level|
      end

      command_route(
        "pipeline history",
        "Show"
      )

      command_route()
    end
  end
end
