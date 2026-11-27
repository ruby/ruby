require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#request_get" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  describe "when passed no block" do
    it "sends a GET request to the passed path and returns the response" do
      response = @http.request_get("/request")
      response.body.should == "Request type: GET"
    end

    it "returns a Net::HTTPResponse object" do
      response = @http.request_get("/request")
      response.should.is_a?(Net::HTTPResponse)
    end
  end

  describe "when passed a block" do
    it "sends a GET request to the passed path and returns the response" do
      response = @http.request_get("/request") {}
      response.body.should == "Request type: GET"
    end

    it "yields the response to the passed block" do
      @http.request_get("/request") do |response|
        response.body.should == "Request type: GET"
      end
    end

    it "returns a Net::HTTPResponse object" do
      response = @http.request_get("/request") {}
      response.should.is_a?(Net::HTTPResponse)
    end
  end
end
