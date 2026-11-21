require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#request_head" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  describe "when passed no block" do
    it "sends a head request to the passed path and returns the response" do
      response = @http.request_head("/request")
      response.body.should == nil
    end

    it "returns a Net::HTTPResponse object" do
      response = @http.request_head("/request")
      response.should.is_a?(Net::HTTPResponse)
    end
  end

  describe "when passed a block" do
    it "sends a head request to the passed path and returns the response" do
      response = @http.request_head("/request") {}
      response.body.should == nil
    end

    it "yields the response to the passed block" do
      @http.request_head("/request") do |response|
        response.body.should == nil
      end
    end

    it "returns a Net::HTTPResponse object" do
      response = @http.request_head("/request") {}
      response.should.is_a?(Net::HTTPResponse)
    end
  end
end
