require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#proxy_basic_auth when passed account, password" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "sets the 'Proxy-Authorization' Header entry for basic authorization" do
    @headers.proxy_basic_auth("rubyspec", "rocks")
    @headers["Proxy-Authorization"].should == "Basic cnVieXNwZWM6cm9ja3M="
  end
end
