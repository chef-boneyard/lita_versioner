require "uri"
require "net/http"
require_relative "jenkins_http/jenkins_http_error"

module LitaVersioner
  class JenkinsHTTP

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
      path = "/#{path}" unless path.start_with?("/")

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
