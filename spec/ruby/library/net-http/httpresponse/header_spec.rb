require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTPResponse#header" do
  it "returns self" do
    res = Net::HTTPUnknownResponse.new("1.0", "???", "test response")
    res.response.should equal(res)
  end
end
