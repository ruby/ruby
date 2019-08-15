require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP.get_response" do
  before :each do
    NetHTTPSpecs.start_server
    @port = NetHTTPSpecs.port
  end

  after :each do
    NetHTTPSpecs.stop_server
  end

  describe "when passed URI" do
    it "returns the response for the specified uri" do
      res = Net::HTTP.get_response(URI.parse("http://localhost:#{@port}/"))
      res.content_type.should == "text/plain"
      res.body.should == "This is the index page."
    end
  end

  describe "when passed host, path, port" do
    it "returns the response for the specified host-path-combination" do
      res = Net::HTTP.get_response('localhost', "/", @port)
      res.content_type.should == "text/plain"
      res.body.should == "This is the index page."
    end
  end
end
