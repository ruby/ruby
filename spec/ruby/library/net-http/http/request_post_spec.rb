require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#request_post" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  describe "when passed no block" do
    it "sends a post request to the passed path and returns the response" do
      response = @http.request_post("/request", "test=test")
      response.body.should == "Request type: POST"
    end

    it "returns a Net::HTTPResponse object" do
      response = @http.request_post("/request", "test=test")
      response.should.is_a?(Net::HTTPResponse)
    end
  end

  describe "when passed a block" do
    it "sends a post request to the passed path and returns the response" do
      response = @http.request_post("/request", "test=test") {}
      response.body.should == "Request type: POST"
    end

    it "yields the response to the passed block" do
      @http.request_post("/request", "test=test") do |response|
        response.body.should == "Request type: POST"
      end
    end

    it "returns a Net::HTTPResponse object" do
      response = @http.request_post("/request", "test=test") {}
      response.should.is_a?(Net::HTTPResponse)
    end
  end
end
