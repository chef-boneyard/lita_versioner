require_relative "bumpbot_handler"
require_relative "../../lita_versioner/format_helpers"

module Lita
  module Handlers
    class BumpbotStatusWebpageHandler < BumpbotHandler
      include LitaVersioner::FormatHelpers

      #
      # Webpage: /bumpbot/handlers/:id/handler.log
      #
      http.get "/bumpbot/handlers/:id/handler.log" do |request, response|
        output.http_response = response
        handler_id = request.env["router.params"][:id]
        handle "Webpage /bumpbot/handlers/#{handler_id}/handler.log" do
          handler_log = File.join(config.sandbox_directory, handler_id.to_s, "handler.log")
          handler = running_handlers.find { |handler| handler.handler_id.to_i == handler_id.to_i }
          begin
            index = 0
            loop do
              buf = redis.getrange("handler_logs:#{handler_id}", index, -1)
              response.write(buf)
              index += buf.size
              break unless handler && running_handlers.include?(handler)
              sleep(0.1)
            end
          rescue Errno::ENOENT
            respond_error!("#{handler_log} not found", status: "404")
          end
        end
      end

      #
      # Webpage: /bumpbot/handlers/:id/sandbox.tgz
      #
      http.get "/bumpbot/handlers/:id/sandbox.tgz" do |request, response|
        output.http_response = response
        handler_id = request.env["router.params"][:id]
        handle "Webpage /bumpbot/handlers/#{handler_id}/sandbox.tgz" do
          handler_sandbox = File.join(config.sandbox_directory, handler_id)
          unless File.exist?(handler_sandbox)
            respond_error!("#{sandbox_directory} not found", status: "404")
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
