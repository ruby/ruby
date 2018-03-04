require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP.post_form when passed URI" do
  before :each do
    NetHTTPSpecs.start_server
    @port = NetHTTPSpecs.port
  end

  after :each do
    NetHTTPSpecs.stop_server
  end

  it "POSTs the passed form data to the given uri" do
    uri = URI.parse("http://localhost:#{@port}/request/body")
    data = { test: :data }

    res = Net::HTTP.post_form(uri, data)
    res.body.should == "test=data"
  end
end
