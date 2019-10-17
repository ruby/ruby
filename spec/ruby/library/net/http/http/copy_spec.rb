require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#copy" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  it "sends a COPY request to the passed path and returns the response" do
    response = @http.copy("/request")
    response.should be_kind_of(Net::HTTPResponse)
    response.body.should == "Request type: COPY"
  end
end
