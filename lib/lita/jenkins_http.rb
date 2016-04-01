require 'uri'
require 'net/http'

module Lita
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
        error_string =<<-ERROR_MESSAGE
Jenkins API Request failed with #{exception.class}

Request Data:
- Base URI: #{base_uri}
- Request Method: #{request_method}
- Request Path: #{request_path}
- Username: #{username}

ERROR_MESSAGE
        if http_exception?
          error_string << <<-HTTP_ERROR_INFO
Exception:\n- #{cause.to_s}
- Response Code: #{cause.response.code}
- Response Body:
#{cause.response.body}
HTTP_ERROR_INFO
        else
          # probably a socket/network issue
          error_string << "Exception:\n- #{cause.to_s}\n"
        end

        error_string
      end

      def http_exception?
        cause.respond_to?(:response)
      end

    end

    ACCEPT = "Accept".freeze
    APPLICATION_JSON = "application/json".freeze

    attr_reader :base_uri
    attr_reader :username
    attr_reader :api_token

    def initialize(base_uri: nil, username: nil, api_token: nil)
      @base_uri = URI.parse(base_uri)
      @username = username
      @api_token = api_token

      @http = nil
    end

    def use_ssl?
      base_uri.scheme == "https"
    end

    def get(path)
      send_request(:Get, path)
    end

    def post(path, parameters)
      full_path = [path, URI.encode_www_form(parameters)].join("?")
      #client.request(request(:Post, full_path))
      send_request(:Post, full_path)
    end

    # @api private
    def send_request(method, path)
      response = client.request(request(method, path))
      response.error! unless response.kind_of?(Net::HTTPSuccess)
      response
    rescue => e
      raise JenkinsHTTPError.new(base_uri: base_uri,
                                 request_method: method,
                                 request_path: path,
                                 username: username,
                                 cause: e)
    end

    # @api private
    def request(method, path)
      req_class = Net::HTTP.const_get(method)
      req = req_class.new(path)
      req.basic_auth(username, api_token)
      req[ACCEPT] = APPLICATION_JSON
      req
    end

    # @api private
    def client
      return @http if @http
      @http = Net::HTTP.new(base_uri.host, base_uri.port)
      @http.use_ssl = use_ssl?
      @http
    end

  end
end
