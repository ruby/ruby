require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#basic_auth when passed account, password" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "sets the 'Authorization' Header entry for basic authorization" do
    @headers.basic_auth("rubyspec", "rocks")
    @headers["Authorization"].should == "Basic cnVieXNwZWM6cm9ja3M="
  end
end
