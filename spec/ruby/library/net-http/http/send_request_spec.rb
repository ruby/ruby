require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#send_request" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)

    # HEAD is special so handled separately
    @methods = %w[
      GET POST PUT DELETE
      OPTIONS
      PROPFIND PROPPATCH LOCK UNLOCK
    ]
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  # TODO: Does only work with GET and POST requests
  describe "when passed type, path" do
    it "sends a HTTP Request of the passed type to the passed path" do
      response = @http.send_request("HEAD", "/request")
      response.body.should be_nil

      (@methods - %w[POST PUT]).each do |method|
        response = @http.send_request(method, "/request")
        response.body.should == "Request type: #{method}"
      end
    end
  end

  describe "when passed type, path, body" do
    it "sends a HTTP Request with the passed body" do
      response = @http.send_request("HEAD", "/request/body", "test=test")
      response.body.should be_nil

      @methods.each do |method|
        response = @http.send_request(method, "/request/body", "test=test")
        response.body.should == "test=test"
      end
    end
  end

  describe "when passed type, path, body, headers" do
    it "sends a HTTP Request with the passed headers" do
      referer = 'https://www.ruby-lang.org/'.freeze

      response = @http.send_request("HEAD", "/request/header", "test=test", "referer" => referer)
      response.body.should be_nil

      @methods.each do |method|
        response = @http.send_request(method, "/request/header", "test=test", "referer" => referer)
        response.body.should include({ "Referer" => referer }.inspect.delete("{}"))
      end
    end
  end
end
