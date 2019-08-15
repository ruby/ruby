require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP.get when passed URI" do
  before :each do
    NetHTTPSpecs.start_server
    @port = NetHTTPSpecs.port
  end

  after :each do
    NetHTTPSpecs.stop_server
  end

  describe "when passed URI" do
    it "returns the body of the specified uri" do
      Net::HTTP.get(URI.parse("http://localhost:#{@port}/")).should == "This is the index page."
    end
  end

  describe "when passed host, path, port" do
    it "returns the body of the specified host-path-combination" do
      Net::HTTP.get('localhost', "/", @port).should == "This is the index page."
    end
  end
end
