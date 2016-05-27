module LitaVersioner
  class JenkinsHTTP

    class JenkinsHTTPError < StandardError

      attr_reader :base_uri
      attr_reader :request_method
      attr_reader :request_path
      attr_reader :username
      attr_reader :cause

      def initialize(base_uri: nil, request_method: nil, request_path: nil, username: nil, cause: nil)
        @base_uri = base_uri
        @request_method = request_method
        @request_path = request_path
        @username = username
        @cause = cause

        super(generate_error_string)
      end

      private

      def generate_error_string
        error_string = <<-ERROR_MESSAGE
Jenkins API Request failed with #{cause.class}

Request Data:
- Base URI: #{base_uri}
- Request Method: #{request_method}
- Request Path: #{request_path}
- Username: #{username}

ERROR_MESSAGE
        if http_exception?
          error_string << <<-HTTP_ERROR_INFO
Exception:\n- #{cause}
- Response Code: #{cause.response.code}
- Response Body:
#{cause.response.body}
HTTP_ERROR_INFO
        else
          # probably a socket/network issue
          error_string << "Exception:\n- #{cause}\n"
        end

        error_string
      end

      def http_exception?
        cause.respond_to?(:response)
      end

    end
  end
end
