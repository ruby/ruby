require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#started?" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.new("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  it "returns true when self has been started" do
    @http.start
    @http.started?.should == true
  end

  it "returns false when self has not been started yet" do
    @http.started?.should == false
  end

  it "returns false when self has been stopped again" do
    @http.start
    @http.finish
    @http.started?.should == false
  end
end
