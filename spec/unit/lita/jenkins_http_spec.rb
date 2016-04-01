require 'spec_helper'
require 'lita/jenkins_http'

RSpec.describe Lita::JenkinsHTTP do

  let(:username) { "bobotclown" }

  let(:api_token) { "0d8ff121f765fd302861209f09f2a0ea" }

  let(:base_uri) { "http://jenkins.example" }

  subject(:jenkins_http) do
    described_class.new(base_uri: base_uri, username: username, api_token: api_token)
  end

  it "has a base URI to the server root path" do
    expect(jenkins_http.base_uri).to eq(URI.parse(base_uri))
  end

  it "has a username for auth" do
    expect(jenkins_http.username).to eq(username)
  end

  it "has an api token for auth" do
    expect(jenkins_http.api_token).to eq(api_token)
  end

  it "configures a Net::HTTP client for the given host and port" do
    expect(jenkins_http.client).to be_a_kind_of(Net::HTTP)
    expect(jenkins_http.client.address).to eq("jenkins.example")
    expect(jenkins_http.client.port).to eq(80)
  end

  context "when given an HTTP (not HTTPS) URL" do

    it "indicates ssl should not be used" do
      expect(jenkins_http.use_ssl?).to be(false)
    end

    it "configures the Net::HTTP client for SSL" do
      expect(jenkins_http.client.use_ssl?).to be(false)
    end
  end

  context "when given an HTTPS URL" do

    let(:base_uri) { "https://jenkins.example" }

    it "indicates ssl should be used" do
      expect(jenkins_http.use_ssl?).to be(true)
    end

    it "configures the Net::HTTP client for SSL" do
      expect(jenkins_http.client.use_ssl?).to be(true)
    end

  end

  describe "creating a request" do

    let(:http_method) { :Get }

    let(:path) { "/jobs/harmony" }

    let(:request) { jenkins_http.request(http_method, path) }

    # https://github.com/ruby/ruby/blob/8dd2435877fae9b13b107cb306c0f4d723451f20/lib/net/http/header.rb#L433-L435
    let(:expected_basic_auth_header) do
      "Basic " + ["#{username}:#{api_token}"].pack("m0")
    end

    it "creates a request for the given path" do
      expect(request.path).to eq(path)
    end

    it "creates a request for the given method" do
      expect(request).to be_a_kind_of(Net::HTTP::Get)
    end

    it "configures the request for HTTP Basic auth" do
      expect(request["authorization"]).to eq(expected_basic_auth_header)
    end

    it "configures the request for JSON content responses" do
      expect(request["accept"]).to eq("application/json")
    end

  end

  describe "making a request" do

    describe "GET" do

      let(:http_method) { :Get }

      let(:path) { "/jobs/harmony" }

      let!(:expected_request) { jenkins_http.request(http_method, path) }


      let(:response) do
        Net::HTTPResponse.send(:response_class, "200").new("1.1", "200", "OK").tap do |r|
          r.instance_variable_set(:@body, "{}")
        end
      end

      it "sends a GET to the HTTP client" do
        # net/http doesn't implement the `==` method for request objects, so we
        # can't `expect(request).to eq(non_object_equality_request)`. Therefore
        # we have to stub the request creation.
        allow(jenkins_http).to receive(:request).with(http_method, path).and_return(expected_request)
        expect(jenkins_http.client).to receive(:request).with(expected_request).and_return(response)
        expect(jenkins_http.get(path)).to eq(response)
      end

    end

    describe "POST" do

      let(:http_method) { :Post }

      let(:path) { "/jobs/harmony" }

      let!(:expected_request) { jenkins_http.request(http_method, path_with_params) }

      let(:response) do
        Net::HTTPResponse.send(:response_class, "200").new("1.1", "200", "OK").tap do |r|
          r.instance_variable_set(:@body, "{}")
        end
      end

      let(:parameters) do
        {
          "GIT_REF" => "v123.456.789",
          "EXPIRE_CACHE" => false
        }
      end

      let(:path_with_params) { "/jobs/harmony?GIT_REF=v123.456.789&EXPIRE_CACHE=false" }

      it "sends a POST to the HTTP client with correct parameters" do
        # net/http doesn't implement the `==` method for request objects, so we
        # can't `expect(request).to eq(non_object_equality_request)`. Therefore
        # we have to stub the request creation.
        allow(jenkins_http).to receive(:request).with(http_method, path_with_params).and_return(expected_request)
        expect(jenkins_http.client).to receive(:request).with(expected_request).and_return(response)
        expect(jenkins_http.post(path, parameters)).to eq(response)
      end

    end

    context "when a request fails" do

      let(:http_method) { :Get }

      let(:path) { "/jobs/harmony" }

      let!(:expected_request) { jenkins_http.request(http_method, path) }

      context "with an HTTP error" do

        let(:response) do
          Net::HTTPResponse.send(:response_class, "500").new("1.1", "500", "Internal Server Error").tap do |r|
            r.instance_variable_set(:@body, "oops")
            r.instance_variable_set(:@read, true)
          end
        end

        it "emits a useful exception" do
          # net/http doesn't implement the `==` method for request objects, so we
          # can't `expect(request).to eq(non_object_equality_request)`. Therefore
          # we have to stub the request creation.
          allow(jenkins_http).to receive(:request).with(http_method, path).and_return(expected_request)
          expect(jenkins_http.client).to receive(:request).with(expected_request).and_return(response)
          expect { jenkins_http.get(path) }.to raise_error(Lita::JenkinsHTTP::JenkinsHTTPError) do |e|
            expect(e.to_s).to eq(<<-ERROR_MESSAGE)
Jenkins API Request failed with Lita::JenkinsHTTP::JenkinsHTTPError

Request Data:
- Base URI: http://jenkins.example
- Request Method: Get
- Request Path: /jobs/harmony
- Username: bobotclown

Exception:
- 500 "Internal Server Error"
- Response Code: 500
- Response Body:
oops
ERROR_MESSAGE
          end
        end

      end

      context "with a network error" do

        let(:network_exception) { Errno::ECONNREFUSED.new('Connection refused - connect(2) for "localhost" port 80') }

        it "emits a useful exception" do
          # net/http doesn't implement the `==` method for request objects, so we
          # can't `expect(request).to eq(non_object_equality_request)`. Therefore
          # we have to stub the request creation.
          allow(jenkins_http).to receive(:request).with(http_method, path).and_return(expected_request)
          expect(jenkins_http.client).to receive(:request).with(expected_request).and_raise(network_exception)
          expect { jenkins_http.get(path) }.to raise_error(Lita::JenkinsHTTP::JenkinsHTTPError) do |e|
            expect(e.to_s).to eq(<<-ERROR_MESSAGE)
Jenkins API Request failed with Lita::JenkinsHTTP::JenkinsHTTPError

Request Data:
- Base URI: http://jenkins.example
- Request Method: Get
- Request Path: /jobs/harmony
- Username: bobotclown

Exception:
- Connection refused - Connection refused - connect(2) for "localhost" port 80
ERROR_MESSAGE
          end
        end

      end


    end
  end
end
