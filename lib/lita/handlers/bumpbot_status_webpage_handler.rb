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
        self.http_response = response
        handler_id = request.env["router.params"][:id]
        handle "Webpage /bumpbot/handlers/#{handler_id}/sandbox/handler.log" do
          handler_log = File.join(config.sandbox_directory, handler_id.to_s, "handler.log")
          handler = running_handlers.find { |handler| handler.handler_id.to_i == handler_id.to_i }
          begin
            File.open(handler_log, "rb") do |file|
              response.headers["Content-Type"] = "text/plain"
              loop do
                response.write(file.read)
                break unless handler && running_handlers.include?(handler)
                sleep(0.1)
              end
            end
          rescue Errno::ENOENT
            error!("#{handler_log} not found", status: "404")
          end
        end
      end

      #
      # Webpage: /bumpbot/handlers/:id/sandbox.tgz
      #
      http.get "/bumpbot/handlers/:id/sandbox.tgz" do |request, response|
        self.http_response = response
        handler_id = request.env["router.params"][:id]
        handle "Webpage /bumpbot/handlers/#{handler_id}/sandbox.tgz" do
          handler_sandbox = File.join(config.sandbox_directory, handler_id)
          unless File.exist?(handler_sandbox)
            error!("#{sandbox_directory} not found", status: "404")
          end
          tarfile = File.join(sandbox_directory, "sandbox.tgz")
          run_command "tar czvf #{tarfile} #{handler_sandbox}"
          response.headers["Content-Type"] = "application/x-compressed"
          response.write(IO.binread(tarfile))
        end
      end

      Lita.register_handler(self)
    end
  end
end
