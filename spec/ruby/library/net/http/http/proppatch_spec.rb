require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#proppatch" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  it "sends an proppatch request to the passed path and returns the response" do
    response = @http.proppatch("/request", "test=test")
    response.body.should == "Request type: PROPPATCH"
  end

  it "returns a Net::HTTPResponse" do
    @http.proppatch("/request", "test=test").should be_kind_of(Net::HTTPResponse)
  end
end
