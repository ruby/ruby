require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'

describe "Net::HTTP#finish" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.new("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  describe "when self has been started" do
    it "closes the tcp connection" do
      @http.start
      @http.finish
      @http.started?.should be_false
    end
  end

  describe "when self has not been started yet" do
    it "raises an IOError" do
      lambda { @http.finish }.should raise_error(IOError)
    end
  end
end
