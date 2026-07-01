require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#head" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  it "sends a HEAD request to the passed path and returns the response" do
    response = @http.head("/request")
    # HEAD requests have no responses
    response.body.should == nil
  end

  it "returns a Net::HTTPResponse" do
    @http.head("/request").should.is_a?(Net::HTTPResponse)
  end
end
