require_relative '../../../../spec_helper'
require 'net/http'
require 'uri'
require_relative 'fixtures/http_server'

describe "Net::HTTP.post" do
  before :each do
    NetHTTPSpecs.start_server
  end

  after :each do
    NetHTTPSpecs.stop_server
  end

  it "sends post request to the specified URI and returns response" do
    response = Net::HTTP.post(
      URI("http://localhost:#{NetHTTPSpecs.port}/request"),
      '{ "q": "ruby", "max": "50" }',
      "Content-Type" => "application/json")
    response.body.should == "Request type: POST"
  end

  it "returns a Net::HTTPResponse" do
    response = Net::HTTP.post(URI("http://localhost:#{NetHTTPSpecs.port}/request"), "test=test")
    response.should be_kind_of(Net::HTTPResponse)
  end

  it "sends Content-Type: application/x-www-form-urlencoded by default" do
    response = Net::HTTP.post(URI("http://localhost:#{NetHTTPSpecs.port}/request/header"), "test=test")
    response.body.should include('"content-type"=>["application/x-www-form-urlencoded"]')
  end

  it "does not support HTTP Basic Auth" do
    response = Net::HTTP.post(
      URI("http://john:qwerty@localhost:#{NetHTTPSpecs.port}/request/basic_auth"),
      "test=test")
    response.body.should == "username: \npassword: "
  end
end

describe "Net::HTTP#post" do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.start("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  it "sends an post request to the passed path and returns the response" do
    response = @http.post("/request", "test=test")
    response.body.should == "Request type: POST"
  end

  it "returns a Net::HTTPResponse" do
    @http.post("/request", "test=test").should be_kind_of(Net::HTTPResponse)
  end

  describe "when passed a block" do
    it "yields fragments of the response body to the passed block" do
      str = ""
      @http.post("/request", "test=test") do |res|
        str << res
      end
      str.should == "Request type: POST"
    end

    it "returns a Net::HTTPResponse" do
      @http.post("/request", "test=test") {}.should be_kind_of(Net::HTTPResponse)
    end
  end
end
