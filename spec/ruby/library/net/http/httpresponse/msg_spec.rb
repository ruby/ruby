require_relative '../../../../spec_helper'
require 'net/http'

describe "Net::HTTPResponse#msg" do
  it "returns self's response message" do
    res = Net::HTTPUnknownResponse.new("1.0", "???", "test response")
    res.message.should == "test response"
  end
end
