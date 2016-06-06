require_relative "bumpbot_handler"
require_relative "../../lita_versioner/format_helpers"

module Lita
  module Handlers
    class BumpbotStatusWebpageHandler < BumpbotHandler
      include LitaVersioner::FormatHelpers

      #
      # Webpage: /bumpbot/handlers/:id/sandbox/handler.log
      #
      http.get "/bumpbot/handlers/:id/sandbox/handler.log" do |request, response|
        handler_id = request.env["router.params"][:id]
        handle_event "Webpage /bumpbot/handlers/#{handler_id}/sandbox/handler.log" do
          handler = running_handlers.find { |handler| handler.handler_id == handler_id.to_i }
          IO.open(File.join(config.sandbox_directory, "handler.log"), "rb:ASCII-8BIT") do |file|
            response.headers["Content-Type"] = "text/plain"
            response.write(file.read)
            # Tail while the handler is still running
            if handler
              while running_handlers[handler]
                select([file])
                response.write(file.read)
              end
            end
          end
        end
      end

      #
      # Webpage: /bumpbot/handlers/:id/sandbox.tgz
      #
      http.get "/bumpbot/handlers/:id/sandbox.tgz" do |request, response|
        handler_id = request.env["router.params"][:id]
        handle_event "Webpage /bumpbot/handlers/#{handler_id}/sandbox.tgz" do
          tarfile = File.join(sandbox_directory, "sandbox.tgz")
          run_command "tar czvf #{tarfile} #{File.join(config.sandbox_directory, handler_id)}"
          response.headers["Content-Type"] = "application/x-compressed"
          response.write(IO.binread(tarfile))
        end
      end

      Lita.register_handler(self)
    end
  end
end
